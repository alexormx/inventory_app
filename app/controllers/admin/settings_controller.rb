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

  def backfill_pending_sale_orders_totals
    run = MaintenanceRun.create!(job_name: "sale_orders.backfill_pending_totals", status: "queued")
    SaleOrders::BackfillPendingTotalsJob.perform_later(run.id)
    flash[:notice] = "Backfill de totales de Sale Orders Pending encolado (##{run.id})."
    redirect_to admin_settings_path
  end

  def delivered_orders_debt_audit
    @result = nil
  end

  def run_delivered_orders_debt_audit
    auto_fix = ActiveModel::Type::Boolean.new.cast(params[:auto_fix])
    create_payments = ActiveModel::Type::Boolean.new.cast(params[:create_payments])
    limit = params[:limit].presence&.to_i
  auditor = Audit::DeliveredOrdersDebtAudit.new(auto_fix: auto_fix, create_payments: create_payments, payment_method: params[:payment_method])

  if request.format.turbo_stream? || request.headers['Accept'].to_s.include?('text/vnd.turbo-stream.html')
      processed = 0
      total = nil
      @result = auditor.run(limit: limit, on_progress: lambda { |p, t|
        processed = p
        total ||= t
        html = ApplicationController.render(
          partial: "admin/settings/progress_delivered_orders_debt_audit",
          locals: { processed: processed, total: total }
        )
        Turbo::StreamsChannel.broadcast_replace_to(
          "audit_progress_channel",
          target: "audit-progress",
          html: html
        )
      })
      respond_to do |format|
        format.turbo_stream do
          render "admin/settings/run_delivered_orders_debt_audit"
        end
        format.html { render :delivered_orders_debt_audit }
      end
    else
      @result = auditor.run(limit: limit)
      render :delivered_orders_debt_audit
    end
  end
end