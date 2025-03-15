class Admin::PurchaseOrdersController < ApplicationController
  before_action :authorize_admin!

  def index
    @purchase_orders = PurchaseOrder.all
  end

  def show
    @purchase_order = PurchaseOrder.find(params[:id])
  end
end
