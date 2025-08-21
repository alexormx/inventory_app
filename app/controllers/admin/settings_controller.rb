class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
  # Últimas ejecuciones de sincronización de inventario (unified)
  @sync_runs = MaintenanceRun.recent_for("inventories.reevaluate_statuses")
  # Últimas ejecuciones de backfill de Sale Orders (unified)
  @so_backfill_runs = MaintenanceRun.recent_for("sale_orders.backfill_totals")
  end

  # Temporal: sincronización de estados de inventario (stub)
  def sync_inventory_statuses
    run = MaintenanceRun.create!(job_name: "inventories.reevaluate_statuses", status: "queued")
    Inventories::ReevaluateStatusesJob.perform_later(run.id)
  flash[:notice] = "Reevaluación de estatus encolada (##{run.id}). Revisa abajo el progreso."
  redirect_to admin_settings_path
  end

  def backfill_sale_orders_totals
    run = MaintenanceRun.create!(job_name: "sale_orders.backfill_totals", status: "queued")
    SaleOrders::BackfillTotalsJob.perform_later(run.id)
    flash[:notice] = "Backfill de totales de Sale Orders encolado (##{run.id}). Revisa abajo el progreso."
    redirect_to admin_settings_path
  end
end