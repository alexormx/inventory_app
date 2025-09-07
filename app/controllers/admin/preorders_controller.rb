class Admin::PreordersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @status = params[:status].presence
    @product_id = params[:product_id].presence
    @user_id = params[:user_id].presence
    @scope = PreorderReservation.all
    @scope = @scope.where(status: PreorderReservation.statuses[@status]) if @status && PreorderReservation.statuses.key?(@status)
    @scope = @scope.where(product_id: @product_id) if @product_id
    @scope = @scope.where(user_id: @user_id) if @user_id
    @scope = @scope.includes(:product, :user).order(:status, :reserved_at)
    @preorders = @scope.page(params[:page]).per(50) rescue @scope

    # Métricas rápidas
    @pending_count = PreorderReservation.pending.count
    @assigned_count = PreorderReservation.assigned.count
    @completed_count = PreorderReservation.completed.count
    @cancelled_count = PreorderReservation.cancelled.count
  end

  def assign_now
    product_id = params[:product_id].presence
    user_id    = params[:user_id].presence

    scope = PreorderReservation.pending
    scope = scope.where(product_id: product_id) if product_id
    scope = scope.where(user_id: user_id) if user_id

    product_ids = scope.distinct.pluck(:product_id)
    processed = 0
    total_assigned = 0
    breakdown = []
    product_ids.each do |pid|
      product = Product.find_by(id: pid)
      next unless product
      begin
        before = Inventory.where(product_id: pid, status: [:pre_reserved, :pre_sold]).count
        Preorders::PreorderAllocator.new(product).call
        after = Inventory.where(product_id: pid, status: [:pre_reserved, :pre_sold]).count
        delta = [after - before, 0].max
        total_assigned += delta
        breakdown << "#{product.product_sku || pid}: #{delta}"
        processed += 1
      rescue => e
        Rails.logger.error "[Preorders#assign_now] product=#{pid} error: #{e.class} #{e.message}"
      end
    end

    summary = "Asignación ejecutada. Productos: #{processed}. Unidades asignadas: #{total_assigned}."
    if breakdown.any?
      summary << " Detalle: " << breakdown.first(5).join(', ')
      summary << "…" if breakdown.size > 5
    end
    redirect_to admin_preorders_path(status: params[:status], product_id: product_id, user_id: user_id),
      notice: summary
  end
end
