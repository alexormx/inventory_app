module Inventories
  class ReevaluateStatusesJob < ApplicationJob
    queue_as :default

    def perform
      service = Inventories::ReevaluateStatusesService.new(relation: Inventory.all)
      service.call
      Rails.logger.info("Inventories::ReevaluateStatusesJob finished with stats: #{service.stats.inspect}")
    end
  end
end
