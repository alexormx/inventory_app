# frozen_string_literal: true

module Admin
  class CollectiblesController < ApplicationController
    before_action :authorize_admin!
    before_action :load_inventory, only: %i[edit update purge_image]

    # Condiciones que identifican una pieza coleccionable (todas menos brand_new)
    COLLECTIBLE_CONDITIONS = (Inventory::ITEM_CONDITIONS.keys - [:brand_new]).map(&:to_s).freeze

    # GET /admin/collectibles
    def index
      @q = params[:q].to_s.strip
      @condition_filter = params[:condition].to_s
      @status_filter = params[:status].to_s

      base = Inventory.where(item_condition: COLLECTIBLE_CONDITIONS)
                      .includes(:product, :inventory_location)

      if @q.present?
        term = "%#{@q.downcase}%"
        base = base.joins(:product).where(
          'LOWER(products.product_name) LIKE ? OR LOWER(products.product_sku) LIKE ?', term, term
        )
      end

      if @condition_filter.present? && @condition_filter != 'all' &&
         COLLECTIBLE_CONDITIONS.include?(@condition_filter)
        base = base.where(item_condition: @condition_filter)
      end

      valid_statuses = Inventory.statuses.keys
      if @status_filter.present? && @status_filter != 'all' && valid_statuses.include?(@status_filter)
        base = base.where(status: @status_filter)
      end

      @counts_by_status = Inventory.where(item_condition: COLLECTIBLE_CONDITIONS).group(:status).count
      @counts_by_condition = Inventory.where(item_condition: COLLECTIBLE_CONDITIONS).group(:item_condition).count

      @collectibles = base
                      .order(Arel.sql('COALESCE(purchase_date, created_at::date) DESC, id DESC'))
                      .page(params[:page]).per(25)
    end

    # GET /admin/collectibles/:id/edit
    def edit
      @categories = Product.distinct.pluck(:category).compact.sort
      @brands = Product.distinct.pluck(:brand).compact.sort
    end

    # PATCH /admin/collectibles/:id
    def update
      attrs = edit_params
      images = attrs.delete(:piece_images)

      if @inventory.update(attrs)
        images.each { |img| @inventory.piece_images.attach(img) if img.present? } if images.present?
        Products::UpdateStatsService.new(@inventory.product).call
        flash[:success] = 'Coleccionable actualizado'
        redirect_to admin_collectibles_path
      else
        flash.now[:alert] = @inventory.errors.full_messages.join(', ')
        @categories = Product.distinct.pluck(:category).compact.sort
        @brands = Product.distinct.pluck(:brand).compact.sort
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/collectibles/:id/images/:image_id
    def purge_image
      image = @inventory.piece_images.find_by(id: params[:image_id])
      image&.purge_later
      redirect_to edit_admin_collectible_path(@inventory), notice: 'Imagen eliminada'
    end

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
                 .select(:id, :product_name, :product_sku, :category, :brand, :selling_price)

      render json: products.map { |p|
        {
          id: p.id,
          product_name: p.product_name,
          product_sku: p.product_sku,
          category: p.category,
          brand: p.brand,
          selling_price: p.selling_price
        }
      }
    end

    private

    def load_inventory
      @inventory = Inventory.where(item_condition: COLLECTIBLE_CONDITIONS).find(params[:id])
    end

    def edit_params
      params.require(:inventory).permit(
        :item_condition, :purchase_cost, :selling_price, :purchase_date,
        :notes, :inventory_location_id, :status, piece_images: []
      )
    end

    def collectible_params
      params.permit(
        :use_existing_product,
        :existing_product_id,
        product: %i[product_name product_sku category brand selling_price description weight width height depth],
        inventory: [:item_condition, :purchase_cost, :selling_price, :purchase_date, :notes, :inventory_location_id, { piece_images: [] }]
      )
    end
  end
end
