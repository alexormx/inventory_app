class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :load_counts, only: [:index, :customers, :suppliers, :admins]
  before_action :set_user, only: [:edit, :update]

  PER_PAGE = 20

  def index
    # Búsqueda y filtro por rol (esquema similar a inventario)
    params[:role] ||= params[:current_role]
    @role_filter = params[:role].presence
    @q = params[:q].to_s.strip

    users = User.order(created_at: :desc)
    if @role_filter.present? && @role_filter != "all"
      users = users.where(role: @role_filter)
    end
    if @q.present?
      term = "%#{@q.downcase}%"
      users = users.where("LOWER(name) LIKE ?", term)
    end

    @users = users.page(params[:page]).per(PER_PAGE)

    # Contadores: globales (no cambian) y filtrados (cambian con búsqueda+filtro)
    @role_counts_global = {
      customers: User.where(role: 'customer').count,
      suppliers: User.where(role: 'supplier').count,
      admins:    User.where(role: 'admin').count
    }

    filtered_counts_scope = User.all
    if @q.present?
      term = "%#{@q.downcase}%"
      filtered_counts_scope = filtered_counts_scope.where("LOWER(name) LIKE ?", term)
    end
    if @role_filter.present? && @role_filter != "all"
      filtered_counts_scope = filtered_counts_scope.where(role: @role_filter)
    end
    @role_counts = {
      customers: filtered_counts_scope.where(role: 'customer').count,
      suppliers: filtered_counts_scope.where(role: 'supplier').count,
      admins:    filtered_counts_scope.where(role: 'admin').count
    }

    @purchase_stats, @sales_stats, @last_visits = compute_stats(@users.map(&:id))
  end

  def customers
    @users = User.where(role: 'customer').order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    @purchase_stats, @sales_stats, @last_visits = compute_stats(@users.map(&:id))
  render :customers, layout: false
  end

  def suppliers
    @users = User.where(role: 'supplier').order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    @purchase_stats, @sales_stats, @last_visits = compute_stats(@users.map(&:id))
  render :suppliers, layout: false
  end

  def admins
    @users = User.where(role: 'admin').order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    @purchase_stats, @sales_stats, @last_visits = compute_stats(@users.map(&:id))
  render :admins, layout: false
  end

  def new
    @user = User.new(role: params[:role].presence || 'customer')
  end

  def create
    @user = User.new(user_params)
    @user.skip_confirmation! if @user.respond_to?(:skip_confirmation!)

    if @user.save
      redirect_to admin_users_path, notice: "User created successfully"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = user_params
    if attrs[:password].blank?
      attrs = attrs.except(:password, :password_confirmation)
    end

    if @user.update(attrs)
      redirect_to admin_users_path, notice: "User updated successfully"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def load_counts
    @counts = {
      customers: User.where(role: 'customer').count,
      suppliers: User.where(role: 'supplier').count,
      admins:    User.where(role: 'admin').count
    }
  end

  def compute_stats(user_ids)
    return [{}, {}, {}] if user_ids.blank?

    purchase_stats = PurchaseOrder.where(user_id: user_ids)
      .group(:user_id)
      .pluck(:user_id, Arel.sql('SUM(total_cost_mxn) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
      .each_with_object({}) { |(uid, total, last_date), h| h[uid] = { total_value: total, last_date: last_date } }

    sales_stats = SaleOrder.where(user_id: user_ids)
      .group(:user_id)
      .pluck(:user_id, Arel.sql('SUM(total_order_value) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
      .each_with_object({}) { |(uid, total, last_date), h| h[uid] = { total_value: total, last_date: last_date } }

    last_visits = VisitorLog.where(user_id: user_ids).group(:user_id).maximum(:last_visited_at)

    [purchase_stats, sales_stats, last_visits]
  end

  def user_params
    params.require(:user).permit(
      :name, :email, :phone, :role, :discount_rate, :created_offline,
      :password, :password_confirmation
    )
  end
end
