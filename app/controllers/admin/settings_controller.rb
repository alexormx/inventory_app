class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
  # Tabla unificada de ejecuciones (todas), paginada (10 por página)
  @runs = MaintenanceRun.order(created_at: :desc).page(params[:page]).per(10)
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

  def delivered_orders_debt_audit
    @result = nil
  end

  def run_delivered_orders_debt_audit
    auto_fix = ActiveModel::Type::Boolean.new.cast(params[:auto_fix])
    create_payments = ActiveModel::Type::Boolean.new.cast(params[:create_payments])
    limit = params[:limit].presence&.to_i
    auditor = Audit::DeliveredOrdersDebtAudit.new(auto_fix: auto_fix, create_payments: create_payments)
    @result = auditor.run(limit: limit)
    render :delivered_orders_debt_audit
  end
end