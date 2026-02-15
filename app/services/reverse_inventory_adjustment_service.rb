# frozen_string_literal: true

class ReverseInventoryAdjustmentService
  class NotReversible < StandardError; end
  class NotApplied < StandardError; end

  def initialize(adjustment, reversed_by: nil, now: Time.current)
    @adjustment = adjustment
    @reversed_by = reversed_by
    @now = now
  end

  def call
    raise NotApplied unless @adjustment.status == 'applied'

    ActiveRecord::Base.transaction do
      @adjustment.inventory_adjustment_lines.each do |line|
        if line.direction == 'increase'
          # Eliminar inventarios creados cuando estén libres y en estado seguro
          line.inventory_adjustment_entries.where(action: 'created').includes(:inventory).find_each do |entry|
            inv = entry.inventory
            if inv.sale_order_id.present? || inv.status.in?(%w[reserved sold pre_reserved pre_sold returned damaged lost scrap])
              raise NotReversible, 'Some created items are allocated or not safely deletable'
            end
            raise NotReversible, 'Some created items are in an unexpected status' unless inv.status.in?(%w[available in_transit marketing])

            inv.destroy!
            entry.update!(action: 'deleted')
          end
        else
          # Restaurar a available los que fueron marcados
          line.inventory_adjustment_entries.where(action: %w[status_changed marked_lost marked_damaged
                                                             marked_scrap]).includes(:inventory).find_each do |entry|
            inv = entry.inventory
            inv.update!(status: :available, status_changed_at: @now, adjustment_reference: nil) if inv.status.in?(%w[damaged lost scrap marketing])
          end
        end
      end

      @adjustment.update!(status: 'draft', reversed_at: @now, reversed_by: @reversed_by)

      product_ids = @adjustment.inventory_adjustment_lines.pluck(:product_id).uniq
      product_ids.each do |pid|
        Products::UpdateStatsService.new(Product.find(pid)).call
      rescue StandardError
        nil
      end
    end
  end
end
