class VisitorLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :ip_address, :path, presence: true

  def self.track(ip:, agent:, path:, user: nil)
    log = VisitorLog.find_or_initialize_by(ip_address: ip, path: path, user: user)
    log.user_agent = agent
    log.visit_count = log.visit_count.to_i + 1
    log.last_visited_at = Time.current

    if log.new_record? || log.country.blank?
      geo = Geocoder.search(ip).first
      if geo
        log.country = geo.country
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
