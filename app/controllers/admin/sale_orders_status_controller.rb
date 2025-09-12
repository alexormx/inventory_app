module Admin
	class SaleOrdersStatusController < ApplicationController
		before_action :authorize_admin!
		before_action :set_sale_order

		def force_pending
			# Placeholder: lógica real debería recalcular totales y desbloquear reservas
			@sale_order.update(status: 'pending') if @sale_order.respond_to?(:status)
			redirect_to admin_sale_order_path(@sale_order), notice: 'Sale order marcada como pending (placeholder).'
		end

		def force_delivered
			# Placeholder: lógica real debería cerrar reservas y marcar entregas
			@sale_order.update(status: 'delivered') if @sale_order.respond_to?(:status)
			redirect_to admin_sale_order_path(@sale_order), notice: 'Sale order marcada como delivered (placeholder).'
		end

		private
		def set_sale_order
			@sale_order = SaleOrder.find(params[:id])
		rescue ActiveRecord::RecordNotFound
			redirect_to admin_sale_orders_path, alert: 'Sale order no encontrada.'
		end
	end
end

