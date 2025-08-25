module SaleOrders
  class BackfillTotalsJob < ApplicationJob
    queue_as :default

    def perform(run_id = nil)
      run = run_id && MaintenanceRun.find_by(id: run_id)
      run&.update(status: "running", started_at: Time.current)

      begin
        count = 0
        updated = 0
  scope = SaleOrder.where("(total_order_value IS NULL OR total_order_value = 0)")
        count = scope.count
        scope.find_each(batch_size: 500) do |so|
          before = so.total_order_value
          so.valid? # triggers compute_financials
          if so.changed? && so.save(validate: false)
            updated += 1
          end
        end
        stats = { total_scanned: count, total_updated: updated }
        run&.update(status: "completed", finished_at: Time.current, stats: stats)
      rescue => e
        run&.update(status: "failed", finished_at: Time.current, error: e.message)
        raise
      end
    end
  end
end
