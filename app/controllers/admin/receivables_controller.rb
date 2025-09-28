class Admin::ReceivablesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @receivables = SaleOrder
      .includes(:user)
      .where("COALESCE(total_order_value,0) > COALESCE(?,0)", 0)
      .select("sale_orders.*, (COALESCE(total_order_value,0) - (SELECT COALESCE(SUM(amount),0) FROM payments WHERE payments.sale_order_id = sale_orders.id AND payments.status='Completed')) AS balance")
      .where("(COALESCE(total_order_value,0) - (SELECT COALESCE(SUM(amount),0) FROM payments WHERE payments.sale_order_id = sale_orders.id AND payments.status='Completed')) > 0")
      .order("due_date NULLS LAST, created_at DESC")
  end
end
