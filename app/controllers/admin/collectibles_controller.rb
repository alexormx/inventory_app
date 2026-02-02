# frozen_string_literal: true

module Admin
  class CollectiblesController < ApplicationController
    before_action :authorize_admin!

    # GET /admin/collectibles/quick_add
    def quick_add
      @product = Product.new
      @inventory = Inventory.new(item_condition: :loose)
      @categories = Product.distinct.pluck(:category).compact.sort
      @brands = Product.distinct.pluck(:brand).compact.sort
    end

    # POST /admin/collectibles/quick_add
    def create_quick_add
      result = Collectibles::QuickAddService.new(
        params: collectible_params,
        user: current_user
      ).call

      if result[:success]
        flash[:success] = result[:message]
        redirect_to admin_product_path(result[:product])
      else
        flash.now[:alert] = result[:errors].join(', ')
        @product = result[:product] || Product.new(collectible_params[:product] || {})
        @inventory = Inventory.new(collectible_params[:inventory] || {})
        @categories = Product.distinct.pluck(:category).compact.sort
        @brands = Product.distinct.pluck(:brand).compact.sort
        render :quick_add, status: :unprocessable_entity
      end
    end

    # GET /admin/collectibles/search_products (AJAX)
    def search_products
      query = params[:query].to_s.strip
      if query.length < 2
        render json: []
        return
      end

      products = Product
        .where('product_name ILIKE ? OR product_sku ILIKE ?', "%#{query}%", "%#{query}%")
        .order(:product_name)
        .limit(10)
        .select(:id, :product_name, :product_sku, :category, :brand, :base_price)

      render json: products.map { |p|
        {
          id: p.id,
          product_name: p.product_name,
          product_sku: p.product_sku,
          category: p.category,
          brand: p.brand,
          base_price: p.base_price
        }
      }
    end

    private

    def collectible_params
      params.permit(
        :use_existing_product,
        :existing_product_id,
        product: [:product_name, :product_sku, :category, :brand, :base_price, :description, :weight, :width, :height, :depth],
        inventory: [:item_condition, :purchase_cost, :selling_price, :notes, :inventory_location_id, piece_images: []]
      )
    end
  end
end
