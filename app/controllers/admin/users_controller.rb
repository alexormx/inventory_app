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
  # Filtros adicionales
  @with_sales      = ActiveModel::Type::Boolean.new.cast(params[:with_sales])
  @with_purchases  = ActiveModel::Type::Boolean.new.cast(params[:with_purchases])
  @active_recent   = ActiveModel::Type::Boolean.new.cast(params[:active_recent]) # últimas 30 días
  @inactive        = ActiveModel::Type::Boolean.new.cast(params[:inactive])      # sin visita o > 90 días
  @with_credit     = ActiveModel::Type::Boolean.new.cast(params[:with_credit])   # con crédito habilitado

  users = User.all
  sort = params[:sort].presence
  dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'

    if @role_filter.present? && @role_filter != "all"
      users = users.where(role: @role_filter)
    end
    if @q.present?
      term = "%#{@q.downcase}%"
      users = users.where("LOWER(name) LIKE ?", term)
    end

    # Subconsultas para estadísticos por usuario (expresiones reutilizables)
    purchases_total_expr = "(SELECT COALESCE(SUM(total_cost_mxn),0) FROM purchase_orders po WHERE po.user_id = users.id)"
    sales_total_expr     = "(SELECT COALESCE(SUM(total_order_value),0) FROM sale_orders so WHERE so.user_id = users.id)"
    last_purchase_expr   = "(SELECT MAX(order_date) FROM purchase_orders po2 WHERE po2.user_id = users.id)"
    last_sale_expr       = "(SELECT MAX(order_date) FROM sale_orders so2 WHERE so2.user_id = users.id)"
    last_visit_expr      = "(SELECT MAX(last_visited_at) FROM visitor_logs vl WHERE vl.user_id = users.id)"

    # Adeudo por usuario: suma, por cada SO del usuario, del faltante (>= 0)
    # faltante_por_so = max(total_order_value - sum(payments.amount Completed), 0)
    balance_due_expr = <<~SQL.squish
      (
        SELECT COALESCE(SUM(
          CASE WHEN (
            so3.total_order_value - (
              SELECT COALESCE(SUM(p.amount),0)
              FROM payments p
              WHERE p.sale_order_id = so3.id AND p.status = 'Completed'
            )
          ) > 0 THEN (
            so3.total_order_value - (
              SELECT COALESCE(SUM(p2.amount),0)
              FROM payments p2
              WHERE p2.sale_order_id = so3.id AND p2.status = 'Completed'
            )
          ) ELSE 0 END
        ), 0)
        FROM sale_orders so3
        WHERE so3.user_id = users.id
      )
    SQL

    purchases_total_sql = "#{purchases_total_expr} AS purchases_total_mxn"
    sales_total_sql     = "#{sales_total_expr} AS sales_total_mxn"
    last_purchase_sql   = "#{last_purchase_expr} AS last_purchase_date"
    last_sale_sql       = "#{last_sale_expr} AS last_sale_date"
    last_visit_sql      = "#{last_visit_expr} AS last_visit_at"
    balance_due_sql     = "#{balance_due_expr} AS balance_due_mxn"

  users = users.select("users.*", purchases_total_sql, sales_total_sql, last_purchase_sql, last_sale_sql, last_visit_sql, balance_due_sql)

    # Aplicar filtros por agregados si están activos
    if @with_sales
      users = users.where(Arel.sql("#{sales_total_expr} > 0"))
    end
    if @with_purchases
      users = users.where(Arel.sql("#{purchases_total_expr} > 0"))
    end
    if @with_credit
      users = users.where(credit_enabled: true)
    end
    if @active_recent
      # En los últimos 30 días
      active_sql = User.sanitize_sql_array(["(#{last_visit_expr}) IS NOT NULL AND (#{last_visit_expr}) >= ?", 30.days.ago])
      users = users.where(active_sql)
    end
    if @inactive
      # Nunca visitó o hace más de 90 días
      users = users.where(
        User.sanitize_sql_array([
          "(#{last_visit_expr} IS NULL OR #{last_visit_expr} < ?)",
          90.days.ago
        ])
      )
    end

    sort_map = {
      'created'        => 'users.created_at',
      'name'           => 'users.name',
      'total_purchases'=> 'purchases_total_mxn',
      'total_sales'    => 'sales_total_mxn',
  'debt'           => 'balance_due_mxn',
      'last_visit'     => 'last_visit_at',
      'last_purchase'  => 'last_purchase_date',
      'last_sale'      => 'last_sale_date'
    }
    if sort_map.key?(sort)
  users = users.reorder(Arel.sql("#{sort_map[sort]} #{dir.upcase}"))
    else
  users = users.reorder(created_at: :desc)
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
    # Replicar filtros agregados para que los contadores reflejen la vista
    if @with_sales
      filtered_counts_scope = filtered_counts_scope.where(Arel.sql("#{sales_total_expr} > 0"))
    end
    if @with_purchases
      filtered_counts_scope = filtered_counts_scope.where(Arel.sql("#{purchases_total_expr} > 0"))
    end
    if @with_credit
      filtered_counts_scope = filtered_counts_scope.where(credit_enabled: true)
    end
    if @active_recent
      active_sql = User.sanitize_sql_array(["(#{last_visit_expr}) IS NOT NULL AND (#{last_visit_expr}) >= ?", 30.days.ago])
      filtered_counts_scope = filtered_counts_scope.where(active_sql)
    end
    if @inactive
  inactive_sql = User.sanitize_sql_array(["(#{last_visit_expr}) IS NULL OR (#{last_visit_expr}) < ?", 90.days.ago])
      filtered_counts_scope = filtered_counts_scope.where(inactive_sql)
    end
    @role_counts = {
      customers: filtered_counts_scope.where(role: 'customer').count,
      suppliers: filtered_counts_scope.where(role: 'supplier').count,
      admins:    filtered_counts_scope.where(role: 'admin').count
    }

  @purchase_stats, @sales_stats, @last_visits = compute_stats(@users.map(&:id))
  end

  # GET /admin/users/suggest?q=al&role=customer|supplier
  def suggest
    q = params[:q].to_s.strip
    role = params[:role].presence
    return render json: [] if q.blank?

    scope = User.all
    scope = scope.where(role: role) if role.present? && %w[customer supplier].include?(role)

    # Priorizar prefijo (empieza con q), luego contener q; ordenar por longitud y alfabético
    q_down = q.downcase
    candidates = scope
      .where("LOWER(name) LIKE ? OR LOWER(name) LIKE ?", "#{q_down}%", "%#{q_down}%")
      .limit(50)

    list = candidates.sort_by { |u| [ (u.name.to_s.downcase.start_with?(q_down) ? 0 : 1), u.name.to_s.length, u.name.to_s.downcase ] }
                     .first(10)
                     .map { |u| { id: u.id, name: u.name } }
    render json: list
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
      :password, :password_confirmation,
      # Credit fields
      :credit_enabled, :default_credit_terms, :credit_limit
    )
  end
end
