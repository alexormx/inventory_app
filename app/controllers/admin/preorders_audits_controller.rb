class Admin::PreordersAuditsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @status = params[:status].presence
    scope = PreorderReservation.all.includes(:product, :user, :sale_order)
    scope = scope.where(status: PreorderReservation.statuses[@status]) if @status && PreorderReservation.statuses.key?(@status)

    @reservations = scope

    # Precalcular pendientes por (SO, producto) a partir de SaleOrderItem
    so_ids = @reservations.map(&:sale_order_id).compact.uniq
    p_ids  = @reservations.map(&:product_id).uniq
    pending_by_pair = {}
    if so_ids.any? && p_ids.any?
      SaleOrderItem.where(sale_order_id: so_ids, product_id: p_ids)
                   .select(:sale_order_id, :product_id, :preorder_quantity, :backordered_quantity)
                   .each do |it|
        key = [it.sale_order_id, it.product_id]
        pending_by_pair[key] ||= 0
        pending_by_pair[key] += it.preorder_quantity.to_i + it.backordered_quantity.to_i
      end
    end

    @to_cancel = [] # [reservation, reason]
    @valid     = []
    @reservations.each do |res|
      if res.sale_order_id.blank?
        @to_cancel << [res, "Sin Sale Order"]
        next
      end
      so = res.sale_order
      if so&.status == 'Canceled'
        @to_cancel << [res, 'SO cancelada']
        next
      end
      sum_pending = pending_by_pair[[res.sale_order_id, res.product_id]].to_i
      if sum_pending <= 0
        @to_cancel << [res, 'Sin líneas pendientes']
      else
        @valid << res
      end
    end

    @summary = {
      total: @reservations.size,
      to_cancel: @to_cancel.size,
      valid: @valid.size
    }
  end

  def fix
    dry = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    # Recalcular el conjunto para evitar usar @var de la vista
    scope = PreorderReservation.all
    so_ids = scope.pluck(:sale_order_id).compact.uniq
    p_ids  = scope.pluck(:product_id).uniq
    pending_by_pair = {}
    if so_ids.any? && p_ids.any?
      SaleOrderItem.where(sale_order_id: so_ids, product_id: p_ids)
                   .select(:sale_order_id, :product_id, :preorder_quantity, :backordered_quantity)
                   .each do |it|
        key = [it.sale_order_id, it.product_id]
        pending_by_pair[key] ||= 0
        pending_by_pair[key] += it.preorder_quantity.to_i + it.backordered_quantity.to_i
      end
    end

    cancelled = 0
    reasons_count = Hash.new(0)
    scope.find_each do |res|
      reason = nil
      if res.sale_order_id.blank?
        reason = 'Sin Sale Order'
      else
        so = SaleOrder.find_by(id: res.sale_order_id)
        if so.nil? || so.status == 'Canceled'
          reason = 'SO inexistente/cancelada'
        else
          sum_pending = pending_by_pair[[res.sale_order_id, res.product_id]].to_i
          reason = 'Sin líneas pendientes' if sum_pending <= 0
        end
      end
      next unless reason
      reasons_count[reason] += 1
      unless dry
        res.update(status: :cancelled, cancelled_at: Time.current)
      end
      cancelled += 1
    end

    msg = dry ? "Simulación: cancelar #{cancelled} preventa(s)." : "Canceladas #{cancelled} preventa(s)."
    if reasons_count.any?
      detail = reasons_count.map { |k, v| "#{k}: #{v}" }.join(', ')
      msg << " Detalle: #{detail}"
    end
    redirect_to admin_preorders_audit_path, notice: msg
  end
end
