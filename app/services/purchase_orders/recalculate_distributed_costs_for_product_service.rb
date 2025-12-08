# frozen_string_literal: true

module PurchaseOrders
  # Recalcula volúmenes, pesos y distribución proporcional de costos adicionales (shipping, tax, other)
  # para TODAS las PurchaseOrderItems de un producto y las otras líneas que conviven en las mismas POs.
  # No filtra por status: opera sobre cualquier estado de la PurchaseOrder.
  #
  # Fórmulas (alineadas con batch endpoint y JS en purchase_order_items.js):
  #   unit_volume = product.length_cm * product.width_cm * product.height_cm
  #   total_line_volume = quantity * unit_volume
  #   unit_additional_cost = total_additional_cost * (unit_volume / total_lines_volume)
  #   unit_compose_cost = unit_cost + unit_additional_cost
  #   unit_compose_cost_in_mxn = unit_compose_cost * exchange_rate
  #   total_line_cost = quantity * unit_compose_cost
  #   total_line_cost_in_mxn = total_line_cost * exchange_rate
  #
  # Retorna Result con métricas.
  class RecalculateDistributedCostsForProductService
    Result = Struct.new(
      :product_id,
      :purchase_orders_scanned,
      :items_recalculated,
      :errors,
      keyword_init: true
    )

    def initialize(product, batch_size: 200)
      @product = product
      @batch_size = batch_size
    end

    def call
      return empty_result('nil product') unless @product
      return empty_result('no id') unless @product.id

      po_ids = PurchaseOrderItem.where(product_id: @product.id).distinct.pluck(:purchase_order_id)
      return empty_result if po_ids.empty?

      purchase_orders_scanned = 0
      items_recalculated = 0
      errors = []

      PurchaseOrder.where(id: po_ids).find_each do |po|
        purchase_orders_scanned += 1
        begin
          recalc_for_purchase_order(po, items_recalculated_ref: items_recalculated)
          # items_recalculated updated inside method (pass by ref via return)
          items_recalculated = @last_items_recalculated
        rescue StandardError => e
          Rails.logger.error("[RecalculateDistributedCostsForProductService] po=#{po.id} #{e.class}: #{e.message}")
          errors << "po #{po.id}: #{e.class}: #{e.message}"
        end
      end

      Result.new(
        product_id: @product.id,
        purchase_orders_scanned: purchase_orders_scanned,
        items_recalculated: items_recalculated,
        errors: errors
      )
    end

    private

    def recalc_for_purchase_order(po, items_recalculated_ref: 0)
      items = po.purchase_order_items.includes(:product).to_a
      return if items.empty?

      # 1) Recalcular volumen/peso totales por línea basado en dimensiones actuales del producto
      items_data = items.map do |item|
        p = item.product
        unit_volume = p.unit_volume_cm3.to_f
        unit_weight = p.unit_weight_gr.to_f
        total_line_volume = (item.quantity.to_f * unit_volume)
        total_line_weight = (item.quantity.to_f * unit_weight)
        {
          item: item,
          unit_volume: unit_volume,
          unit_weight: unit_weight,
          total_line_volume: total_line_volume,
          total_line_weight: total_line_weight
        }
      end

      total_lines_volume = items_data.sum { |d| d[:total_line_volume] }
      total_lines_weight = items_data.sum { |d| d[:total_line_weight] }

      total_additional_cost = po.shipping_cost.to_d + po.tax_cost.to_d + po.other_cost.to_d
      exchange_rate = (po.exchange_rate.presence || 1).to_d

      # 2) Calcular costos por línea
      updates = []
      items_data.each do |d|
        item = d[:item]
        unit_volume = d[:unit_volume]
        qty = item.quantity.to_f
        unit_cost = item.unit_cost.to_d
        line_volume = qty * unit_volume
        volume_ratio = total_lines_volume.positive? ? (line_volume / total_lines_volume) : 0.0
        line_additional_cost = (total_additional_cost * volume_ratio)
        unit_additional_cost = qty.positive? ? (line_additional_cost / qty).round(2) : 0
        unit_compose_cost = (unit_cost + unit_additional_cost).round(2)
        unit_compose_cost_mxn = (unit_compose_cost * exchange_rate).round(2)
        total_line_cost = (qty * unit_compose_cost).round(2)
        total_line_cost_mxn = (total_line_cost * exchange_rate).round(2)

        updates << [item.id, {
          total_line_volume: d[:total_line_volume],
          total_line_weight: d[:total_line_weight],
          unit_additional_cost: unit_additional_cost,
          unit_compose_cost: unit_compose_cost,
          unit_compose_cost_in_mxn: unit_compose_cost_mxn,
          total_line_cost: total_line_cost,
          total_line_cost_in_mxn: total_line_cost_mxn,
          updated_at: Time.current
        }]
      end

      PurchaseOrderItem.transaction do
        # Bulk persist (individual update_columns to bypass callbacks y mejorar rendimiento)
        updates.each do |(id, attrs)|
          PurchaseOrderItem.where(id: id).update_all(attrs)
        end

        # 3) Recalcular totales de la PO (similar a batch endpoint lógica)
        subtotal = items.sum { |it| (it.quantity.to_f * it.unit_cost.to_f) }.round(2)
        total_order_cost = (subtotal + total_additional_cost).round(2)
        total_cost_mxn = (total_order_cost * exchange_rate).round(2)

        po.update_columns(
          subtotal: subtotal,
          total_volume: total_lines_volume,
          total_weight: total_lines_weight,
          total_order_cost: total_order_cost,
          total_cost_mxn: total_cost_mxn,
          costs_distributed_at: Time.current,
          updated_at: Time.current
        )

        # 4) Propagar costos unitarios compuestos (en MXN) a cada pieza de inventario asociada
        #    para que las valuaciones de inventario reflejen la redistribución.
        #    Nota: Se actualizan TODAS las piezas (incluidas vendidas/danadas) ya que el usuario
        #    requiere ver reflejado el nuevo costo unitario; si se quisiera preservar historia
        #    se podría limitar a estados libres y crear un ajuste diferencial.
        inventory_cost_map = updates.to_h { |(id, attrs)| [id, attrs[:unit_compose_cost_in_mxn]] }
        inventory_cost_map.each_slice(50) do |slice|
          slice.each do |poi_id, new_cost_mxn|
            next if new_cost_mxn.nil?

            Inventory.where(purchase_order_item_id: poi_id).find_each do |inv|
              prev_cost = inv.purchase_cost
              inv.update_columns(purchase_cost: new_cost_mxn, updated_at: Time.current)
              begin
                InventoryEvent.create!(
                  inventory: inv,
                  product_id: inv.product_id,
                  event_type: 'distributed_cost_applied',
                  previous_purchase_cost: prev_cost,
                  new_purchase_cost: new_cost_mxn,
                  metadata: { purchase_order_item_id: poi_id, purchase_order_id: po.id }
                )
              rescue StandardError => e
                Rails.logger.error "[RecalculateDistributedCostsForProductService] event error inv=#{inv.id} #{e.class}: #{e.message}"
              end
            end
          end
        end
      end

      @last_items_recalculated = (items_recalculated_ref + updates.size)
    end

    def empty_result(msg = nil)
      Result.new(product_id: @product&.id, purchase_orders_scanned: 0, items_recalculated: 0, errors: msg ? [msg] : [])
    end
  end
end
