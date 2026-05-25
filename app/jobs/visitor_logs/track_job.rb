# frozen_string_literal: true

module VisitorLogs
  class TrackJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(ip:, agent:, path:, user_id: nil, referrer: nil)
      VisitorLog.track(
        ip: ip,
        agent: agent,
        path: path,
        user_id: user_id,
        referrer: referrer
      )
    end
  end
end
