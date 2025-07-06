class VisitorLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :ip_address, :path, presence: true

  def self.track(ip:, agent:, path:, user: nil)
    log = VisitorLog.find_or_initialize_by(ip_address: ip, path: path, user: user)
    log.user_agent = agent
    log.visit_count = log.visit_count.to_i + 1
    log.last_visited_at = Time.current
    log.save!
    rescue ActiveRecord::RecordNotUnique
      retry
  end
end
