# frozen_string_literal: true

module Admin
  # Historial de carritos durables (clientes con sesión): activos, convertidos
  # en orden, vencidos y otros. Sólo lectura. Los carritos de invitados viven
  # en el navegador y aparecen aquí hasta que el visitante inicia sesión.
  class ShoppingCartsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    TABS = {
      'active' => %w[active],
      'converted' => %w[converted],
      'expired' => %w[expired],
      'other' => %w[merged cleared],
      'all' => ShoppingCart::STATUSES
    }.freeze

    def index
      @status = TABS.key?(params[:status]) ? params[:status] : 'active'
      @counts = ShoppingCart.group(:status).count
      @query = params[:q].to_s.strip
      @carts = with_figures(filtered).order(Arel.sql('COALESCE(shopping_carts.closed_at, shopping_carts.last_activity_at) DESC'))
                                     .page(params[:page]).per(25)
    end

    def show
      @cart = ShoppingCart.includes(:user, shopping_cart_items: :product).find(params[:id])
      @held_inventory_ids = CartInventoryHold.active.for_cart(@cart).pluck(:shopping_cart_item_id).tally
    end

    private

    def filtered
      scope = ShoppingCart.where(status: TABS.fetch(@status)).includes(:user)
      return scope if @query.blank?

      like = "%#{ShoppingCart.sanitize_sql_like(@query)}%"
      scope.joins(:user).where('users.email ILIKE :q OR users.name ILIKE :q', q: like)
    end

    # Líneas, unidades, valor a precio actual y apartados vigentes, en SQL.
    def with_figures(scope)
      scope.select(<<~SQL.squish)
        shopping_carts.*,
        (SELECT COUNT(*) FROM shopping_cart_items i WHERE i.shopping_cart_id = shopping_carts.id) AS lines_count,
        (SELECT COALESCE(SUM(i.quantity), 0) FROM shopping_cart_items i WHERE i.shopping_cart_id = shopping_carts.id) AS units_count,
        (SELECT COALESCE(SUM(i.quantity * p.selling_price), 0) FROM shopping_cart_items i
           JOIN products p ON p.id = i.product_id WHERE i.shopping_cart_id = shopping_carts.id) AS estimated_value,
        (SELECT COUNT(*) FROM cart_inventory_holds h
           WHERE h.shopping_cart_id = shopping_carts.id AND h.expires_at > clock_timestamp()) AS active_holds
      SQL
    end
  end
end
