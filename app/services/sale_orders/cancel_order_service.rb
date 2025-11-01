# frozen_string_literal: true

module SaleOrders
  # Cancela una Sale Order y libera todos los inventarios reservados/vendidos
  # Uso:
  #   SaleOrders::CancelOrderService.new(sale_order).call
  #
  # Retorna: la sale_order actualizada
  # Lanza: ActiveRecord::RecordInvalid si no se puede guardar
  class CancelOrderService
    attr_reader :sale_order

    def initialize(sale_order)
      @sale_order = sale_order
    end

    def call
      return sale_order if sale_order.status == "Canceled"

      ActiveRecord::Base.transaction do
        # 1. Liberar inventarios y remover asociación PRIMERO
        release_inventories!

        # 2. Actualizar estado de la orden usando update! para respetar transacciones
        #    (el callback release_reserved_if_canceled no hará nada relevante luego de liberar arriba)
        sale_order.update!(status: "Canceled")

        # 3. Actualizar product stats para los productos afectados
        update_product_stats!

        # 4. Log/auditoría (opcional)
        Rails.logger.info "[CancelOrderService] SO #{sale_order.id} canceled, #{@released_count} inventories released"
      end

      sale_order.reload
    end

    private

    def release_inventories!
      # Encontrar todos los inventarios asociados a esta sale_order
      # Puede ser por sale_order_id directo O por sale_order_item_id que pertenece a esta orden
      releasable_statuses = %w[reserved pre_reserved sold pre_sold in_transit]

      # IDs de sale_order_items de esta orden
      sale_order_item_ids = sale_order.sale_order_items.pluck(:id)

      # Construir query de forma segura para manejar arrays vacíos
      inventories_to_release = Inventory.where(status: releasable_statuses)

      if sale_order_item_ids.present?
        inventories_to_release = inventories_to_release.where(
          'sale_order_id = ? OR sale_order_item_id IN (?)',
          sale_order.id,
          sale_order_item_ids
        )
      else
        inventories_to_release = inventories_to_release.where(sale_order_id: sale_order.id)
      end

      # Guardar product_ids antes de hacer update_all
      @product_ids = inventories_to_release.pluck(:product_id).uniq

      @released_count = inventories_to_release.update_all(
        status: Inventory.statuses[:available],
        sale_order_id: nil,
        sale_order_item_id: nil,
        status_changed_at: Time.current,
        updated_at: Time.current
      )

      # Asegurar que cualquier inventory vinculado por sale_order_item_id también quede limpio,
      # incluso si su status ya era 'available' y no entró en el primer update_all
      sale_order_item_ids = sale_order.sale_order_items.pluck(:id)
      if sale_order_item_ids.present?
        Inventory.where(sale_order_item_id: sale_order_item_ids)
                 .update_all(sale_order_item_id: nil, updated_at: Time.current)
      end

      Rails.logger.info "[CancelOrderService] SO #{sale_order.id}: Released #{@released_count} inventories"
    end

    def update_product_stats!
      return unless @product_ids.present?

      @product_ids.each do |product_id|
        Products::UpdateStatsService.new(Product.find(product_id)).call
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn "[CancelOrderService] Product #{product_id} not found for stats update"
      end
    end
  end
end
