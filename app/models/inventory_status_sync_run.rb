class InventoryStatusSyncRun < ApplicationRecord
  enum :status,
       { queued: "queued", running: "running", completed: "completed", failed: "failed" },
       default: :queued, prefix: :sync_status
  
  # Stats guardadas como JSON (requiere ActiveRecord >= 7.1 para coder: JSON)
  serialize :stats, coder: JSON
  
  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end
end
