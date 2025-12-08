# frozen_string_literal: true

module Admin
  class PreordersController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_preorder, only: %i[destroy cancel]

    def index
      status_param_present = params.key?(:status)
      @status = status_param_present ? params[:status].presence : 'pending'
      @product_id = params[:product_id].presence
      @user_id = params[:user_id].presence
      @scope = PreorderReservation.all
      @scope = @scope.where(status: PreorderReservation.statuses[@status]) if @status && @status != 'all' && PreorderReservation.statuses.key?(@status)
      @scope = @scope.where(product_id: @product_id) if @product_id
      @scope = @scope.where(user_id: @user_id) if @user_id
      @scope = @scope.includes(:product, :user, :sale_order).order(:status, :reserved_at)
      @preorders = begin
        @scope.page(params[:page]).per(50)
      rescue StandardError
        @scope
      end

      # Precalcular SO Item ID por (sale_order_id, product_id) para evitar N+1
      pairs = @preorders.map { |r| [r.sale_order_id, r.product_id] }.select { |sid, pid| sid.present? && pid.present? }
      if pairs.any?
        so_ids = pairs.map(&:first).uniq
        p_ids  = pairs.map(&:last).uniq
        items = SaleOrderItem.where(sale_order_id: so_ids, product_id: p_ids).select(:id, :sale_order_id, :product_id)
        @so_item_by_pair = {}
        items.each do |it|
          key = [it.sale_order_id, it.product_id]
          @so_item_by_pair[key] ||= it.id
        end
      else
        @so_item_by_pair = {}
      end

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
          before = Inventory.where(product_id: pid, status: %i[pre_reserved pre_sold]).count
          Preorders::PreorderAllocator.new(product).call
          after = Inventory.where(product_id: pid, status: %i[pre_reserved pre_sold]).count
          delta = [after - before, 0].max
          total_assigned += delta
          breakdown << "#{product.product_sku || pid}: #{delta}"
          processed += 1
        rescue StandardError => e
          Rails.logger.error "[Preorders#assign_now] product=#{pid} error: #{e.class} #{e.message}"
        end
      end

      summary = "Asignación ejecutada. Productos: #{processed}. Unidades asignadas: #{total_assigned}."
      if breakdown.any?
        summary << ' Detalle: ' << breakdown.first(5).join(', ')
        summary << '…' if breakdown.size > 5
      end
      redirect_to admin_preorders_path(status: params[:status], product_id: product_id, user_id: user_id),
                  notice: summary
    end

    # DELETE /admin/preorders/:id
    def destroy
      @preorder.update(status: :cancelled, cancelled_at: Time.current)
      redirect_to admin_preorders_path, notice: 'Preventa cancelada'
    end

    # POST /admin/preorders/:id/cancel (alias más explícito)
    def cancel
      @preorder.update(status: :cancelled, cancelled_at: Time.current)
      redirect_to admin_preorders_path, notice: 'Preventa cancelada'
    end

    private

    def set_preorder
      @preorder = PreorderReservation.find(params[:id])
    end
  end
end
