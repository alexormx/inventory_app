# frozen_string_literal: true

module Admin
  # Qué productos guardan los clientes, para decidir qué volver a pedir.
  class FavoritesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    RANKING_LIMIT = 200
    PERIODS = { '7' => 'Últimos 7 días', '30' => 'Últimos 30 días', '90' => 'Últimos 90 días' }.freeze

    def index
      @days = PERIODS.key?(params[:days]) ? params[:days] : nil
      @without_stock = params[:without_stock] == '1'

      rows = ranking_scope.to_a
      product_ids = rows.map(&:product_id)
      @products = Product.where(id: product_ids).with_attached_product_images.index_by(&:id)
      @on_hand = Inventory.customer_on_hand.where(product_id: product_ids).group(:product_id).count
      @in_transit = Inventory.where(product_id: product_ids, status: :in_transit, sale_order_id: nil)
                             .group(:product_id).count
      @rows = rows.select { |row| @products.key?(row.product_id) }
      @open_total = Favorite.open.count
      @customers_total = Favorite.open.distinct.count(:user_id)
    end

    def show
      @product = Product.find(params[:id])
      @open_favorites = @product.favorites.open.includes(:user).order(created_at: :desc)
      @purchased_favorites = @product.favorites.where(removal_reason: 'purchased').includes(:user)
                                     .order(removed_at: :desc).limit(50)
    end

    private

    def ranking_scope
      scope = Favorite.all
      scope = scope.where(created_at: params[:days].to_i.days.ago..) if @days
      scope = scope.where.not(product_id: Inventory.customer_on_hand.select(:product_id)) if @without_stock
      scope.group(:product_id)
           .select(:product_id,
                   'COUNT(*) FILTER (WHERE removed_at IS NULL) AS open_count',
                   "COUNT(*) FILTER (WHERE removed_at IS NULL AND source = 'abandoned_cart') AS abandoned_count",
                   "COUNT(*) FILTER (WHERE removal_reason = 'purchased') AS purchased_count")
           .having('COUNT(*) FILTER (WHERE removed_at IS NULL) > 0')
           .order(Arel.sql('open_count DESC, purchased_count DESC'))
           .limit(RANKING_LIMIT)
    end
  end
end
