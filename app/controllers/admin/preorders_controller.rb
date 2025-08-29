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
end
