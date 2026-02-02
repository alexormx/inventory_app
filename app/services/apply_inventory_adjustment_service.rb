# frozen_string_literal: true

class ApplyInventoryAdjustmentService
  class InsufficientStock < StandardError; end
  class EmptyAdjustment < StandardError; end
  class AlreadyApplied < StandardError; end

  def initialize(adjustment, applied_by: nil, now: Time.current)
    @adjustment = adjustment
    @applied_by = applied_by
    @now = now
  end

  def call
    raise AlreadyApplied if @adjustment.status == 'applied'

    lines = @adjustment.inventory_adjustment_lines.to_a
    raise EmptyAdjustment if lines.empty?

    ActiveRecord::Base.transaction do
      @adjustment.generate_reference_if_needed!(@now)
      @adjustment.save! if @adjustment.changed?

      # Pre-validación: agrupar decreases por producto para validar suma total
      decrease_totals = Hash.new(0)
      lines.select { |l| l.direction == 'decrease' }.each do |line|
        decrease_totals[line.product_id] += line.quantity
      end
      decrease_totals.each do |product_id, total_qty|
        available_scope = Inventory.where(product_id: product_id, status: :available)
        raise InsufficientStock, "Insufficient available inventory for product #{product_id} (needed #{total_qty})" if available_scope.count < total_qty
      end

      movements = 0

      lines.each do |line|
        if line.direction == 'increase'
          line.quantity.times do
            inv = Inventory.create!(
              product_id: line.product_id,
              purchase_cost: line.unit_cost || 0,
              item_condition: line.item_condition || :brand_new,
              selling_price: line.selling_price,
              status: :available,
              status_changed_at: @now,
              source: 'ledger_adjustment',
              notes: @adjustment.reference,
              adjustment_reference: @adjustment.reference
            )
            line.inventory_adjustment_entries.create!(inventory: inv, action: 'created')
            movements += 1
          end
        else
          # FIFO: más antiguos primero, respetando la condición si se especifica
          scope = Inventory.where(product_id: line.product_id, status: :available)
          scope = scope.where(item_condition: line.item_condition) if line.item_condition.present? && line.item_condition != 'brand_new'
          to_mark = scope.order(:created_at).limit(line.quantity).lock
          raise InsufficientStock, "Concurrent modification reduced stock for product #{line.product_id}" if to_mark.size < line.quantity

          target_status = case line.reason
                          when 'lost' then :lost
                          when 'damaged' then :damaged
                          when 'scrap' then :scrap
                          when 'marketing' then :marketing
                          else :scrap
                          end
          to_mark.each do |inv|
            inv.update!(status: target_status, status_changed_at: @now, adjustment_reference: @adjustment.reference)
            action = case target_status
                     when :lost then 'marked_lost'
                     when :damaged then 'marked_damaged'
                     when :scrap then 'marked_scrap'
                     else 'status_changed'
                     end
            line.inventory_adjustment_entries.create!(inventory: inv, action: action)
            movements += 1
          end
        end
      end

      @adjustment.update!(status: 'applied', applied_at: @now, applied_by: @applied_by)

      # Recalcular métricas de productos afectados
      product_ids = lines.map(&:product_id).uniq
      product_ids.each do |pid|

        Products::UpdateStatsService.new(Product.find(pid)).call
      rescue StandardError
        nil

      end

      movements
    end
  end
end

