class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Settings logic
  end

  # Temporal: sincronización de estados de inventario (stub)
  def sync_inventory_statuses
    # Por ahora solo stub: no hace cambios hasta recibir detalles
    flash[:notice] = "Sincronización de inventario encolada (temporal). Detalla los criterios para continuar."
    redirect_to admin_settings_path
  end
end
