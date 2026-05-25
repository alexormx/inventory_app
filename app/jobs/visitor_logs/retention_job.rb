# frozen_string_literal: true

module VisitorLogs
  class RetentionJob < ApplicationJob
    queue_as :default

    DEFAULT_AGE_DAYS = 180

    def perform(age_days: DEFAULT_AGE_DAYS)
      cutoff = age_days.to_i.days.ago
      count = VisitorLog.where('last_visited_at < ?', cutoff).delete_all
      Rails.logger.info("[VisitorLogs::RetentionJob] Deleted #{count} rows older than #{age_days} days")
      count
    end
  end
end
