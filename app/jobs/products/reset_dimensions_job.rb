module Products
  class ResetDimensionsJob < ApplicationJob
    queue_as :default

    DEFAULTS = {
      weight_gr: 50.0,
      length_cm: 8.0,
      width_cm:  4.0,
      height_cm: 4.0
    }.freeze

    def perform(run_id = nil)
      run = MaintenanceRun.find_by(id: run_id) if run_id
      start_run!(run)
      total = Product.count
      processed = 0
  updated = 0
  changed_product_ids = []

      Product.find_each do |product|
        begin
          attrs = {}
          DEFAULTS.each do |k,v|
            current = product.send(k)
            # Overwrite a defaults si difiere (permitiendo que valores ya iguales no generen write I/O)
            if current.to_f.round(2) != v
              attrs[k] = v
            end
          end
          if attrs.any?
            product.update_columns(attrs) # omit callbacks; control manual del recálculo
            updated += 1
            changed_product_ids << product.id
          end
          processed += 1
          tick_progress(run, processed, total, updated)
        rescue => e
          Rails.logger.error("[ResetDimensionsJob] product #{product.id} error: #{e.message}")
        end
      end

      pos_recalculated = 0
      if changed_product_ids.any?
        po_ids = PurchaseOrderItem.where(product_id: changed_product_ids).distinct.pluck(:purchase_order_id)
        PurchaseOrder.where(id: po_ids).find_each do |po|
          recalc_po(po)
          pos_recalculated += 1
        end
      end

      finish_run!(run, updated: updated, total: total, pos_recalculated: pos_recalculated)
    rescue => e
      fail_run!(run, e)
      raise
    end

    private

    def start_run!(run)
      return unless run
      run.update!(status: :running, started_at: Time.current)
    end

    def tick_progress(run, processed, total, updated)
      return unless run
      run.update_columns(stats: { processed: processed, total: total, updated: updated }) if processed % 25 == 0
    end

  def finish_run!(run, stats_hash)
      return unless run
      run.update!(status: :completed, finished_at: Time.current, stats: (run.stats || {}).merge(stats_hash))
    end

    def fail_run!(run, error)
      return unless run
      run.update!(status: :failed, finished_at: Time.current, stats: (run.stats || {}).merge(error: error.message))
    end

    def recalc_po(po)
      items = po.purchase_order_items.includes(:product)
      return if items.empty?
      line_data = items.map do |item|
        p = item.product
        unit_volume = p.length_cm.to_f * p.width_cm.to_f * p.height_cm.to_f
        unit_weight = p.weight_gr.to_f
        [item, unit_volume, unit_weight, unit_volume * item.quantity.to_i, unit_weight * item.quantity.to_i]
      end
      total_volume = line_data.sum { |_,_,_,lv,_| lv }
      total_weight = line_data.sum { |_,_,_,_,lw| lw }
      total_additional_cost = po.shipping_cost.to_d + po.tax_cost.to_d + po.other_cost.to_d
      exchange_rate = po.exchange_rate.to_d.nonzero? || 1.to_d
      subtotal = 0.to_d
      line_data.each do |item, unit_volume, _unit_weight, line_volume, line_weight|
        ratio = total_volume > 0 ? (unit_volume / total_volume) : 0
        unit_additional_cost = (total_additional_cost * ratio).round(2)
        unit_compose_cost = (item.unit_cost.to_d + unit_additional_cost).round(2)
        unit_compose_cost_mxn = (unit_compose_cost * exchange_rate).round(2)
        line_total_cost = (unit_compose_cost * item.quantity.to_i).round(2)
        line_total_cost_mxn = (line_total_cost * exchange_rate).round(2)
        subtotal += (item.unit_cost.to_d * item.quantity.to_i)
        item.update_columns(
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
      po.update_columns(
        subtotal: subtotal,
        total_volume: total_volume,
        total_weight: total_weight,
        total_order_cost: total_order_cost,
        total_cost_mxn: total_cost_mxn
      )
    rescue => e
      Rails.logger.error("[ResetDimensionsJob] recalc_po #{po.id} error: #{e.message}")
    end
  end
end
