class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Settings logic
  end

  # Temporal: sincronización de estados de inventario (stub)
  def sync_inventory_statuses
  # Encolar una reevaluación de estatus en background
  Inventories::ReevaluateStatusesJob.perform_later
  flash[:notice] = "Reevaluación de estatus de inventario encolada. Puedes continuar usando el sistema."
  redirect_to admin_settings_path
  end
end
