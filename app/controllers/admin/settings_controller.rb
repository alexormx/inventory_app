# frozen_string_literal: true

module Admin
  class SettingsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      # Tabla unificada de ejecuciones (todas), paginada (10 por página)
      @runs = MaintenanceRun.order(created_at: :desc).page(params[:page]).per(10)
      # Métricas rápidas de reconciliación inventario
      begin
        @last_reconciliation_event = InventoryEvent.where(event_type: %w[reconciliation_orphan_destroyed reconciliation_missing_created])
                                                   .order(created_at: :desc).limit(1).first
        window_from = 24.hours.ago
        scope24 = InventoryEvent.where('created_at >= ? AND event_type IN (?)', window_from, %w[reconciliation_orphan_destroyed reconciliation_missing_created])
        @recon_24_orphans = scope24.where(event_type: 'reconciliation_orphan_destroyed').count
        @recon_24_created = scope24.where(event_type: 'reconciliation_missing_created').count
      rescue StandardError => e
        Rails.logger.warn "[Settings#index] reconciliation metrics error: #{e.class}: #{e.message}"
      end
      if request.post? && params[:save_tax]
        SiteSetting.set('tax_enabled', params[:tax_enabled] == 'true', 'boolean')
        SiteSetting.set('tax_rate_percent', params[:tax_rate_percent].to_f.round(2), 'integer')
        flash[:notice] = 'Configuración de impuestos guardada.'
        redirect_to admin_settings_path and return
      end
      if request.post? && params[:save_ui]
        SiteSetting.set('language_switcher_enabled', params[:language_switcher_enabled] == 'true', 'boolean')
        SiteSetting.set('dark_mode_enabled', params[:dark_mode_enabled] == 'true', 'boolean')
        flash[:notice] = 'Configuración de interfaz guardada.'
        redirect_to admin_settings_path and return
      end
      if request.post? && params[:save_payments]
        SiteSetting.set('payment_bank_account', params[:payment_bank_account].to_s.strip, 'string')
        SiteSetting.set('payment_oxxo_number', params[:payment_oxxo_number].to_s.strip, 'string')
        flash[:notice] = 'Datos de pago guardados.'
        redirect_to admin_settings_path and return
      end
      return unless request.post? && params[:save_eta]

      preorder_days = params[:preorder_eta_days].to_i
      backorder_days = params[:backorder_eta_days].to_i
      preorder_days = 60 if preorder_days <= 0
      backorder_days = 60 if backorder_days <= 0
      SiteSetting.set('preorder_eta_days', preorder_days, 'integer')
      SiteSetting.set('backorder_eta_days', backorder_days, 'integer')
      flash[:notice] = 'Tiempos estimados guardados.'
      redirect_to admin_settings_path and return
    
    end

    # Temporal: sincronización de estados de inventario (stub)
    def sync_inventory_statuses
      run = MaintenanceRun.create!(job_name: 'inventories.reevaluate_statuses', status: 'queued')
      Inventories::ReevaluateStatusesJob.perform_later(run.id)
      flash[:notice] = "Reevaluación de estatus encolada (##{run.id}). Revisa abajo el progreso."
      redirect_to admin_settings_path
    end

    def backfill_sale_orders_totals
      run = MaintenanceRun.create!(job_name: 'sale_orders.backfill_totals', status: 'queued')
      SaleOrders::BackfillTotalsJob.perform_later(run.id)
      flash[:notice] = "Backfill de totales de Sale Orders encolado (##{run.id}). Revisa abajo el progreso."
      redirect_to admin_settings_path
    end

    def backfill_inventory_sale_order_item_id
      run = MaintenanceRun.create!(job_name: 'inventories.backfill_so_item_link', status: 'running', started_at: Time.current)
      begin
        result = Inventories::BackfillSaleOrderItemId.new.call
        run.update!(status: 'completed', finished_at: Time.current, stats: result.to_h)
        flash[:notice] = "Backfill completado: actualizados=#{result.inventories_updated}, pares=#{result.pairs_processed}, omitidos=#{result.pairs_skipped}."
      rescue StandardError => e
        run.update!(status: 'failed', finished_at: Time.current, error: "#{e.class}: #{e.message}")
        flash[:alert] = "Error en backfill: #{e.message}"
      end
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
            partial: 'admin/settings/progress_delivered_orders_debt_audit',
            locals: { processed: processed, total: total }
          )
          Turbo::StreamsChannel.broadcast_replace_to(
            'audit_progress_channel',
            target: 'audit-progress',
            html: html
          )
        })
        respond_to do |format|
          format.turbo_stream do
            render 'admin/settings/run_delivered_orders_debt_audit'
          end
          format.html { render :delivered_orders_debt_audit }
        end
      else
        @result = auditor.run(limit: limit)
        render :delivered_orders_debt_audit
      end
    end

    def reset_product_dimensions
      run = MaintenanceRun.create!(job_name: 'products.reset_dimensions', status: :queued)
      Products::ResetDimensionsJob.perform_later(run.id)
      flash[:notice] = "Reset de dimensiones/peso encolado (##{run.id}). Revisa el listado de ejecuciones."
      redirect_to admin_settings_path
    end

    def recalc_all_po_alpha_costs
      run = MaintenanceRun.create!(job_name: 'purchase_orders.recalc_alpha_costs', status: :queued)
      PurchaseOrders::RecalculateAllAlphaCostsJob.perform_later(run.id)
      flash[:notice] = "Recalculo masivo de alpha/compose costs encolado (##{run.id})."
      redirect_to admin_settings_path
    end

    def mark_distributed_costs
      run = MaintenanceRun.create!(job_name: 'purchase_orders.mark_distributed_costs', status: :running, started_at: Time.current)

      dry_run = params[:dry_run] == 'true'
      tolerance = (params[:tolerance].presence || '0.01').to_f

      begin
        candidates = []
        skipped = []

        PurchaseOrder.where(costs_distributed_at: nil).find_each do |po|
          lines = po.purchase_order_items.to_a

          if lines.empty?
            skipped << { id: po.id, reason: 'sin_lineas' }
            next
          end

          unless lines.all? { |li| li.total_line_cost.present? }
            skipped << { id: po.id, reason: 'lineas_sin_total_line_cost' }
            next
          end

          sum_lines = lines.sum { |li| li.total_line_cost.to_d }
          matches_total = (sum_lines - po.total_order_cost.to_d).abs <= tolerance
          matches_subtotal = (sum_lines - po.subtotal.to_d).abs <= tolerance

          if matches_total || matches_subtotal
            candidates << {
              id: po.id,
              sum_lines: sum_lines.to_f,
              matched: matches_total ? 'total' : 'subtotal'
            }
          else
            skipped << {
              id: po.id,
              reason: 'suma_no_coincide'
            }
          end
        end

        marked_count = 0
        unless dry_run
          candidates.each do |c|
            po = PurchaseOrder.find(c[:id])
            po.update_column(:costs_distributed_at, po.updated_at || Time.current)
            marked_count += 1
          end
        end

        result = {
          dry_run: dry_run,
          tolerance: tolerance,
          candidates_count: candidates.count,
          skipped_count: skipped.count,
          marked_count: marked_count,
          sample_candidates: candidates.first(5),
          sample_skipped: skipped.first(5)
        }

        run.update!(
          status: 'completed',
          finished_at: Time.current,
          stats: result
        )

        flash[:notice] = if dry_run
                           "Dry run completado: #{candidates.count} candidatas, #{skipped.count} omitidas. No se aplicaron cambios."
                         else
                           "✅ Marcadas #{marked_count} Purchase Orders con costs_distributed_at."
                         end
      rescue StandardError => e
        run.update!(status: 'failed', finished_at: Time.current, error: "#{e.class}: #{e.message}")
        flash[:alert] = "Error: #{e.message}"
      end

      redirect_to admin_settings_path
    end
  end
end