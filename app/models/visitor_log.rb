# frozen_string_literal: true

class VisitorLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :ip_address, :path, presence: true

  # Upsert a (ip, path, user_id) row. Increments visit_count, refreshes
  # last_visited_at and referrer, and geocodes the IP on first sight or
  # when the stored country is missing / looks like a name rather than
  # an ISO-3166 alpha-2 code (so existing rows heal as they're touched).
  def self.track(ip:, agent:, path:, user_id: nil, referrer: nil)
    log = VisitorLog.find_or_initialize_by(ip_address: ip, path: path, user_id: user_id)
    log.user_agent = agent
    log.visit_count = log.visit_count.to_i + 1
    log.last_visited_at = Time.current
    log.referrer = referrer if referrer.present?

    if log.new_record? || log.country.blank? || log.country.to_s.length != 2
      geo = Geocoder.search(ip).first
      if geo
        log.country = geo.country_code.presence || geo.country
        log.region = geo.state
        log.city = geo.city
        log.latitude = geo.latitude
        log.longitude = geo.longitude
      end
    end

    log.save!
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
