module Inventories
  class ReevaluateStatusesService
    # Recalcula el status de cada Inventory basado en:
    # - Estado del PurchaseOrder: Pending/In Transit -> in_transit, Delivered -> available
    # - Enlace a SaleOrder y su estado/pago:
    #   * Si está en tránsito y tiene sale_order: Pending -> pre_reserved, Confirmed|Shipped|Delivered -> pre_sold
    #   * Si está entregado (PO Delivered) y tiene sale_order:
    #       - Pending -> reserved
    #       - Confirmed|Shipped -> sold (si queremos marcar como vendido al confirmar/pagar)
    #       - Delivered -> sold
    # - No reemplaza estados manuales: damaged, lost, returned, scrap, marketing
    # - No toca sold para no revertir ventas ya asentadas
    TERMINAL_STATUSES = %w[damaged lost returned scrap marketing sold].freeze

    def initialize(relation: Inventory.all)
      @relation = relation
      @stats = Hash.new(0)
    end

    attr_reader :stats

    def call
      # Procesar en batches para evitar memoria
      @relation.in_batches(of: 1000) do |batch|
        updates = []
        now = Time.current
        batch.includes(:purchase_order, :sale_order).each do |inv|
          current = inv.status.to_s
          if TERMINAL_STATUSES.include?(current)
            @stats["skipped_terminal"] += 1
            next
          end

          po_status = inv.purchase_order&.status
          so = inv.sale_order
          so_status = so&.status

          new_status = compute_status(current, po_status, so_status)
          next if new_status.nil? || new_status.to_s == current

          updates << {
            id: inv.id,
            status: Inventory.statuses[new_status],
            status_changed_at: now
          }
          @stats["changed_#{current}_to_#{new_status}"] += 1
        end

        # Aplicar en bulk
        bulk_update_status(updates) if updates.any?
      end

      self
    end

    private

    def compute_status(current, po_status, so_status)
      # Reglas base por estado de PO
      case po_status
      when "Pending", "In Transit"
        # En tránsito
        if so_status.present?
          return :pre_reserved if so_status == "Pending"
          return :pre_sold if %w[Confirmed Shipped Delivered].include?(so_status)
        end
        return :in_transit
      when "Delivered"
        # Ya entregado a almacén
        if so_status.present?
          return :reserved if so_status == "Pending"
          return :sold if %w[Confirmed Shipped Delivered].include?(so_status)
        end
        return :available
      when "Canceled"
        # Si el PO fue cancelado y el item no es terminal, márcalo como scrap
        return :scrap
      else
        # Sin PO: mantener si está disponible/reservado/in_transit
        return current.to_sym if %w[available reserved in_transit].include?(current)
      end
    end

    def bulk_update_status(rows)
      ids = rows.map { |r| r[:id] }
      return if ids.empty?
      # Generar cláusulas CASE para status y status_changed_at
      status_cases = rows.map { |r| "WHEN id=#{r[:id]} THEN #{r[:status]}" }.join(" ")
      time = rows.first[:status_changed_at]
      ts = ActiveRecord::Base.connection.quote(time)
      sql = <<-SQL.squish
        UPDATE inventories
        SET status = CASE #{status_cases} END,
            status_changed_at = #{ts},
            updated_at = #{ts}
        WHERE id IN (#{ids.join(',')})
      SQL
      ActiveRecord::Base.connection.execute(sql)
    end
  end
end
