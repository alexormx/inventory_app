# frozen_string_literal: true

module Admin
  class InventoryReconciliationsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def create
      mode = (params[:mode].presence || 'all').to_sym
      dry  = params[:dry_run] == '1'
      service = ::InventoryReconciliation::ReconcilePurchaseOrderLinksService.new(dry_run: dry, mode: mode)
      result = service.call
      if result.errors.any?
        flash[:alert] = "La reconciliación falló y no aplicó cambios: #{result.errors.join(', ')}"
      else
        flash[:notice] = "Reconciliación (mode=#{mode}, dry_run=#{dry}) => huérfanos: #{result.destroyed_orphans}, creados: #{result.created_missing}"
      end
    rescue StandardError => e
      flash[:alert] = "Error en reconciliación: #{e.message}"
    ensure
      redirect_back fallback_location: admin_inventory_audit_path
    end
  end
end
