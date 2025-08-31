# Recalcula costos adicionales y costos compuestos de todos los PurchaseOrders
# que contienen un product dado, redistribuyendo shipping/tax/other según volumen
# (manteniendo lógica actual basada en volumen).
module PurchaseOrders
  class RecalculateCostsForProductService
    def initialize(product)
      @product = product
    end

    def call
      po_ids = PurchaseOrderItem.where(product_id: @product.id).distinct.pluck(:purchase_order_id)
      PurchaseOrder.where(id: po_ids).find_each do |po|
        recalc_purchase_order(po)
      end
    end

    private

    def recalc_purchase_order(po)
      items = po.purchase_order_items.includes(:product)
      return if items.empty?

      # Recalcular volumen/peso unitario con posibles nuevas dimensiones
      line_data = items.map do |item|
        p = item.product
        unit_volume = p.length_cm.to_f * p.width_cm.to_f * p.height_cm.to_f
        unit_weight = p.weight_gr.to_f
        line_volume = unit_volume * item.quantity.to_i
        line_weight = unit_weight * item.quantity.to_i
        [item, unit_volume, unit_weight, line_volume, line_weight]
      end

      total_volume = line_data.sum { |_, _, _, lv, _| lv }
      total_weight = line_data.sum { |_, _, _, _, lw| lw }

      total_additional_cost = po.shipping_cost.to_d + po.tax_cost.to_d + po.other_cost.to_d
      exchange_rate = po.exchange_rate.to_d.nonzero? || 1.to_d

      subtotal = 0.to_d

      ActiveRecord::Base.transaction do
        line_data.each do |item, unit_volume, _unit_weight, line_volume, line_weight|
          volume_ratio = total_volume > 0 ? (unit_volume / total_volume) : 0
          unit_additional_cost = (total_additional_cost * volume_ratio).round(2)
          unit_compose_cost = (item.unit_cost.to_d + unit_additional_cost).round(2)
          unit_compose_cost_mxn = (unit_compose_cost * exchange_rate).round(2)
          line_total_cost = (unit_compose_cost * item.quantity.to_i).round(2)
          line_total_cost_mxn = (line_total_cost * exchange_rate).round(2)

          subtotal += (item.unit_cost.to_d * item.quantity.to_i)

          item.update!(
            unit_additional_cost: unit_additional_cost,
            unit_compose_cost: unit_compose_cost,
            unit_compose_cost_in_mxn: unit_compose_cost_mxn,
            total_line_volume: line_volume,
            total_line_weight: line_weight,
            total_line_cost: line_total_cost,
            total_line_cost_in_mxn: line_total_cost_mxn
          )
        end

        total_order_cost = (subtotal + total_additional_cost).round(2)
        total_cost_mxn = (total_order_cost * exchange_rate).round(2)
        po.update!(
          subtotal: subtotal,
          total_volume: total_volume,
          total_weight: total_weight,
          total_order_cost: total_order_cost,
          total_cost_mxn: total_cost_mxn
        )
      end
    rescue => e
      Rails.logger.error("[RecalculateCostsForProductService] PO #{po.id} error: #{e.message}")
    end
  end
end
