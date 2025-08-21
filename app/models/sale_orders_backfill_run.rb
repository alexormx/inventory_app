class SaleOrdersBackfillRun < ApplicationRecord
  enum :status,
       { queued: "queued", running: "running", completed: "completed", failed: "failed" },
       default: :queued

  serialize :stats, coder: JSON

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end
end
