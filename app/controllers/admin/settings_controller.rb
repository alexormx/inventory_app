class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
  # Últimas ejecuciones de sincronización de inventario
  @sync_runs = InventoryStatusSyncRun.order(created_at: :desc).limit(10)
  end

  # Temporal: sincronización de estados de inventario (stub)
  def sync_inventory_statuses
  run = InventoryStatusSyncRun.create!(status: :queued)
  Inventories::ReevaluateStatusesJob.perform_later(run.id)
  flash[:notice] = "Reevaluación de estatus encolada (##{run.id}). Revisa abajo el progreso."
  redirect_to admin_settings_path
  end
end
