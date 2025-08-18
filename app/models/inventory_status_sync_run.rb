class InventoryStatusSyncRun < ApplicationRecord
  enum status: {
    queued: "queued",
    running: "running",
    completed: "completed",
    failed: "failed"
  }, _default: :queued

  # Guardar estadísticas del servicio como JSON serializado en texto
  serialize :stats, JSON

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end
end
