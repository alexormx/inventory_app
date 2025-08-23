module SaleOrders
  class BackfillPendingTotalsJob < ApplicationJob
    queue_as :default

    def perform(run_id = nil)
      run = run_id && MaintenanceRun.find_by(id: run_id)
      run&.update(status: "running", started_at: Time.current)

      begin
        scope = SaleOrder.where(status: 'Pending')
        total = scope.count
        updated = 0
        scope.find_each(batch_size: 500) do |so|
          dyn = so.compute_dynamic_totals
          next if dyn[:total].zero?
          # Solo actualizar si el valor almacenado difiere
          if so.total_order_value.to_d != dyn[:total]
            so.subtotal = dyn[:subtotal]
            so.total_tax = dyn[:tax]
            so.total_order_value = dyn[:total]
            so.save(validate: false)
            updated += 1
          end
        end
        run&.update(status: "completed", finished_at: Time.current, stats: { pending_scanned: total, pending_updated: updated })
      rescue => e
        run&.update(status: "failed", finished_at: Time.current, error: e.message)
        raise
      end
    end
  end
end
