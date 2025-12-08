# frozen_string_literal: true

module Inventories
  class ReevaluateStatusesJob < ApplicationJob
    queue_as :default

    def perform(run_id = nil)
      run = run_id && MaintenanceRun.find_by(id: run_id)
      run&.update(status: 'running', started_at: Time.current)

      begin
        service = Inventories::ReevaluateStatusesService.new(relation: Inventory.all)
        service.call
        run&.update(status: 'completed', finished_at: Time.current, stats: service.stats)
        Rails.logger.info("Inventories::ReevaluateStatusesJob finished with stats: #{service.stats.inspect}")
      rescue StandardError => e
        run&.update(status: 'failed', finished_at: Time.current, error: e.message)
        Rails.logger.error("Inventories::ReevaluateStatusesJob failed: #{e.message}")
        raise
      end
    end
  end
end
