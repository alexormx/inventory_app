# frozen_string_literal: true

module WhatsappRequests
  class CleanupDraftsJob < ApplicationJob
    queue_as :default

    DEFAULT_AGE_DAYS = 30

    def perform(age_days: DEFAULT_AGE_DAYS)
      cutoff = age_days.to_i.days.ago
      scope = WhatsappRequest.where(status: WhatsappRequest.statuses[:draft])
                             .where('updated_at < ?', cutoff)
      count = scope.count
      scope.find_each(&:destroy)
      Rails.logger.info("[WhatsappRequests::CleanupDraftsJob] Removed #{count} drafts older than #{age_days} days")
      count
    end
  end
end
