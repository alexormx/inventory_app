module PurchaseOrders
  # Recalcula unit_additional_cost (alpha cost) y costos compuestos de TODAS las Purchase Orders
  # Útil tras un cambio masivo de dimensiones o costos extra.
  class RecalculateAllAlphaCostsJob < ApplicationJob
    queue_as :default

    def perform(run_id = nil)
      run = MaintenanceRun.find_by(id: run_id) if run_id
      start_run!(run)
      po_ids = PurchaseOrder.pluck(:id)
      total = po_ids.size
      processed = 0
      updated = 0

      po_ids.each_slice(50) do |batch|
        PurchaseOrder.where(id: batch).includes(purchase_order_items: :product).find_each do |po|
          begin
            updated += 1 if recalc_po(po)
          rescue => e
            Rails.logger.error("[RecalculateAllAlphaCostsJob] PO #{po.id} error: #{e.message}")
          ensure
            processed += 1
            tick_progress(run, processed, total, updated)
          end
        end
      end

      finish_run!(run, total: total, updated: updated)
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
      if processed % 10 == 0 || processed == total
        run.update_columns(stats: { processed: processed, total: total, updated: updated })
      end
    end

    def finish_run!(run, stats_hash)
      return unless run
      run.update!(status: :completed, finished_at: Time.current, stats: (run.stats || {}).merge(stats_hash))
    end

    def fail_run!(run, error)
      return unless run
      run.update!(status: :failed, finished_at: Time.current, stats: (run.stats || {}).merge(error: error.message))
    end

    # Devuelve true si recalculó
    def recalc_po(po)
      items = po.purchase_order_items
      return false if items.empty?

      line_data = items.map do |item|
        p = item.product
        unit_volume = p.length_cm.to_f * p.width_cm.to_f * p.height_cm.to_f
        [item, unit_volume, unit_volume * item.quantity.to_i]
      end
      total_volume = line_data.sum { |_,_,lv| lv }
      total_additional_cost = po.shipping_cost.to_d + po.tax_cost.to_d + po.other_cost.to_d
      exchange_rate = po.exchange_rate.to_d.nonzero? || 1.to_d
      subtotal = 0.to_d

      changed = false
      line_data.each do |item, unit_volume, line_volume|
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
          total_line_cost: line_total_cost,
          total_line_cost_in_mxn: line_total_cost_mxn
        )
        changed = true
      end

      total_order_cost = (subtotal + total_additional_cost).round(2)
      total_cost_mxn = (total_order_cost * exchange_rate).round(2)
      po.update_columns(
        subtotal: subtotal,
        total_volume: total_volume,
        total_order_cost: total_order_cost,
        total_cost_mxn: total_cost_mxn
      ) if changed
      changed
    end
  end
end
