class Admin::SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_supplier, only: [:edit, :update]

  def index
    @suppliers = User.where(role: "supplier").order(created_at: :desc).page(params[:page]).per(20)
    user_ids = @suppliers.map(&:id)
    @purchase_stats = PurchaseOrder.where(user_id: user_ids)
      .group(:user_id)
      .pluck(:user_id, Arel.sql("SUM(total_cost_mxn) AS total_value"), Arel.sql("MAX(order_date) AS last_date"))
      .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
    @sales_stats = SaleOrder.where(user_id: user_ids)
      .group(:user_id)
      .pluck(:user_id, Arel.sql("SUM(total_order_value) AS total_value"), Arel.sql("MAX(order_date) AS last_date"))
      .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
    @last_visits = VisitorLog.where(user_id: user_ids).group(:user_id).maximum(:last_visited_at)
  end

  def new
    @supplier = User.new(role: "supplier")
  end

  def create
    @supplier = User.new(supplier_params.merge(role: "supplier"))
    @supplier.password = Devise.friendly_token.first(12)

    if @supplier.save
      redirect_to admin_suppliers_path, notice: "Supplier created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @supplier.update(supplier_params)
      redirect_to admin_suppliers_path, notice: "Supplier updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_supplier
    @supplier = User.find(params[:id])
  end

  def supplier_params
    params.require(:user).permit(:name, :email, :phone, :address)
  end
end
