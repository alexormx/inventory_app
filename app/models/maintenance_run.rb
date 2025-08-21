class MaintenanceRun < ApplicationRecord
  enum :status,
       { queued: "queued", running: "running", completed: "completed", failed: "failed" },
       default: :queued

  serialize :stats, coder: JSON

  scope :recent_for, ->(job_name, limit_count = 10) { where(job_name: job_name).order(created_at: :desc).limit(limit_count) }

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end
end
