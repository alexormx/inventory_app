# frozen_string_literal: true

module Admin
  class ProductsController < ApplicationController
    include CustomAttributesParam
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_product, only: %i[show edit update destroy purge_image activate deactivate assign_preorders
                                       discontinue reverse_discontinue]
    before_action :fix_custom_attributes_param, only: %i[create update]
    before_action :load_counts, only: %i[index drafts active inactive]

    # Tamaño de página para listados en este controlador (cambiar aquí para afectar todas las vistas)
    PER_PAGE = 9

    def index
      @q = params[:q].to_s.strip
      current_status = params[:status].presence || 'all'
      scope = Product.all
      scope = scope.where(status: current_status) if current_status != 'all'
      if @q.present?
        term = "%#{@q.downcase}%"
        scope = scope.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end
      @sort = params[:sort].presence || 'recent'
      scope = apply_sort(scope, @sort)
      @products = scope.page(params[:page]).per(PER_PAGE)

      # Pre-cargar conteos de inventario para evitar N+1 queries
      product_ids = @products.map(&:id)
      @inventory_counts = Inventory.where(product_id: product_ids)
                                   .group(:product_id, :status)
                                   .count

      compute_counts
    end

    def show; end

    def new
      @product = Product.new
    end

    def edit; end

    def create
      @product = Product.new(product_params)
      if @product.save
        flash[:notice] = 'Product created successfully.'
        redirect_to admin_products_path
      else
        flash.now[:alert] = 'Error creating product.'
        render :new
      end
    end

    def update
      # Attach new images *without removing existing ones*
      params[:product][:product_images]&.each do |image|
        @product.product_images.attach(image)
      end

      if @product.update(product_params.except(:product_images))
        flash[:notice] = 'Product updated successfully.'
        redirect_to admin_product_path(@product)
      else
        flash.now[:alert] = 'Error updating product.'
        render :edit
      end
    end

    def assign_preorders
      Preorders::PreorderAllocator.new(@product).call
      redirect_to admin_product_path(@product), notice: 'Preórdenes asignadas (si había disponibilidad).'
    end

    def destroy
      if @product.destroy
        flash[:notice] = 'Product deleted successfully.'
        redirect_to admin_products_path
      else
        flash[:alert] = 'Error deleting product.'
        redirect_to admin_product_path(@product)
      end
    end

    def purge_image
      image = @product.product_images.find(params[:image_id])
      image_id = image.id
      image.purge # or purge_later for async

      respond_to do |format|
        format.html { redirect_to edit_admin_product_path(@product), notice: 'Image removed successfully.' }
        format.turbo_stream { render turbo_stream: turbo_stream.remove("image_#{image_id}")} # optional: for dynamic deletion
      end
    end

    def search
      q = params[:query].to_s.strip
      return render json: [] if q.blank? || q.length < 3

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"

      products = Product
                 .includes(product_images_attachments: :blob) # avoids N+1 when calling variant
                 .where(
                   'LOWER(product_name) LIKE LOWER(?) OR LOWER(product_sku) LIKE LOWER(?)',
                   pattern, pattern
                 )
                 .order(:product_name)
                 .limit(20)

      # Pre-fetch inventory counts to avoid N+1
      product_ids = products.map(&:id)
      inventory_counts = Inventory.where(product_id: product_ids)
                                  .group(:product_id, :status)
                                  .count

      render json: products.map { |product|
        thumb_url = if product.product_images.attached?
                      begin
                        url_for(product.product_images.first.variant(resize_to_limit: [40, 40]).processed)
                      rescue StandardError => e
                        Rails.logger.warn("[Admin::ProductsController#search] Variant error for product=#{product.id}: #{e.class} #{e.message}")
                        helpers.asset_path('placeholder.png')
                      end
                    else
                      helpers.asset_path('placeholder.png')
                    end

        # Calculate inventory stats for this product
        available = inventory_counts[[product.id, 'available']].to_i
        reserved = inventory_counts[[product.id, 'reserved']].to_i
        in_transit = inventory_counts[[product.id, 'in_transit']].to_i
        pre_reserved = inventory_counts[[product.id, 'pre_reserved']].to_i

        {
          id: product.id,
          product_name: product.product_name,
          product_sku: product.product_sku,
          weight_gr: product.weight_gr,
          length_cm: product.length_cm,
          width_cm: product.width_cm,
          height_cm: product.height_cm,
          unit_volume_cm3: product.unit_volume_cm3.to_f,
          unit_weight_gr: product.unit_weight_gr.to_f,
          thumbnail_url: thumb_url,
          # Inventory info
          stock_available: available,
          stock_reserved: reserved,
          stock_in_transit: in_transit,
          stock_pre_reserved: pre_reserved,
          stock_sellable: available + in_transit  # What can potentially be sold
        }
      }
    end

    def activate
      @product.update(status: 'active')
      @source_tab = params[:source_tab].presence || 'all'
      # Recompute counts AFTER status change
      load_counts
      prepare_source_tab_collection(@source_tab)
      # Provide collection expected by turbo stream partial
      @products = @source_products
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_products_path(status: params[:source_tab]), notice: 'Product activated' }
      end
    end

    def deactivate
      @product.update(status: 'inactive')
      @source_tab = params[:source_tab].presence || 'all'
      load_counts
      prepare_source_tab_collection(@source_tab)
      @products = @source_products
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_products_path(status: params[:source_tab]), notice: 'Product deactivated' }
      end
    end

    # Mark product as discontinued and convert all "new" inventory to "misb" with new price
    def discontinue
      price = params[:price].to_d
      if price <= 0
        return render json: { error: 'El precio debe ser mayor a 0' }, status: :unprocessable_entity
      end

      service = Products::DiscontinueService.new(@product)
      result = service.discontinue!(misb_price: price)

      render json: {
        status: 'ok',
        message: "Producto descontinuado. #{result[:converted_count]} piezas convertidas a MISB.",
        converted_count: result[:converted_count]
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # Reverse discontinuation: convert all "misb" inventory back to "new"
    def reverse_discontinue
      new_price = params[:price].present? ? params[:price].to_d : nil

      service = Products::DiscontinueService.new(@product)
      result = service.reverse!(new_price: new_price)

      render json: {
        status: 'ok',
        message: "Producto restaurado a producción. #{result[:converted_count]} piezas convertidas a Nuevo.",
        converted_count: result[:converted_count]
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # --- Vistas por estado ---
    def drafts
      @q = params[:q].to_s.strip
      scope = Product.where(status: 'draft').includes(:product_images_attachments)
      if @q.present?
        term = "%#{@q.downcase}%"
        scope = scope.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end
      @sort = params[:sort].presence
      scope = apply_sort(scope, @sort)
      @products = scope.page(params[:page]).per(PER_PAGE)
      compute_counts
      render :drafts, layout: false
    end

    def active
      @q = params[:q].to_s.strip
      scope = Product.where(status: 'active').includes(:product_images_attachments)
      if @q.present?
        term = "%#{@q.downcase}%"
        scope = scope.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end
      @sort = params[:sort].presence
      scope = apply_sort(scope, @sort)
      @products = scope.page(params[:page]).per(PER_PAGE)
      compute_counts
      render :active, layout: false
    end

    def inactive
      @q = params[:q].to_s.strip
      scope = Product.where(status: 'inactive').includes(:product_images_attachments)
      if @q.present?
        term = "%#{@q.downcase}%"
        scope = scope.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end
      @sort = params[:sort].presence
      scope = apply_sort(scope, @sort)
      @products = scope.page(params[:page]).per(PER_PAGE)
      compute_counts
      render :inactive, layout: false
    end

    private

    def load_counts
      compute_counts
    end

    def compute_counts
      q = params[:q].to_s.strip
      base = Product.all
      if q.present?
        term = "%#{q.downcase}%"
        base = base.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end
      # Aplicar también el filtro de status actual para los contadores inferiores
      current_status = params[:status].presence || 'all'
      filtered_base = base
      filtered_base = filtered_base.where(status: current_status) if current_status != 'all'
      # Globales (no dependen de q)
      @counts_global = {
        draft: Product.where(status: 'draft').count,
        active: Product.where(status: 'active').count,
        inactive: Product.where(status: 'inactive').count
      }
      # Inferiores (dependen de q)
      @counts = {
        draft: filtered_base.where(status: 'draft').count,
        active: filtered_base.where(status: 'active').count,
        inactive: filtered_base.where(status: 'inactive').count
      }
    end

    def fix_custom_attributes_param
      return if params[:product].blank?

      coerce_custom_attributes!(params[:product]) # <- del concern
    end

    def prepare_source_tab_collection(tab)
      scope = Product.all
      scope = case tab
              when 'draft' then scope.where(status: 'draft')
              when 'active' then scope.where(status: 'active')
              when 'inactive' then scope.where(status: 'inactive')
              else scope # 'all'
              end
      # sort param reuse minimal (recent vs name vs others handled by apply_sort)
      @sort = params[:sort].presence
      scope = apply_sort(scope, @sort) if respond_to?(:apply_sort)
      @source_products = scope.page(params[:page]).per(PER_PAGE)
    end

    # Strong parameters for product
    def product_params
      params.expect(
        product: [:product_sku,
                  :barcode,
                  :supplier_product_code,
                  :brand,
                  :category,
                  :description,
                  :product_name,
                  :reorder_point,
                  :selling_price,
                  :maximum_discount,
                  :minimum_price,
                  :discount_limited_stock,
                  :backorder_allowed,
                  :preorder_available,
                  :status,
                  :product_images,
                  :weight_gr,
                  :length_cm,
                  :width_cm,
                  :height_cm,
                  :launch_date,
                  { custom_attributes: {}, # allow custom attributes as a hash
                    product_images: [] }] # allow multiple file uploads
      )
    end

    def set_product
      id = params[:id] || params[:product_id]
      begin
        @product = Product.friendly.find(id)
      rescue ActiveRecord::RecordNotFound
        respond_to do |format|
          format.html { redirect_to admin_products_path, alert: 'Product not found.' }
          format.json { render json: { error: 'Product not found' }, status: :not_found }
        end
      end
    end

    def apply_sort(scope, sort_param)
      case sort_param
      when 'name_asc'        then scope.order(Arel.sql('LOWER(product_name) ASC'))
      when 'name_desc'       then scope.order(Arel.sql('LOWER(product_name) DESC'))
      when 'name'            then scope.order(Arel.sql('LOWER(product_name) ASC'))
      when 'sku'             then scope.order(Arel.sql('LOWER(product_sku) ASC'))
      when 'price_asc'       then scope.order(selling_price: :asc)
      when 'price_desc'      then scope.order(selling_price: :desc)
      when 'stock_asc'       then scope.order(total_purchase_quantity: :asc)
      when 'stock_desc'      then scope.order(total_purchase_quantity: :desc)
      when 'purchase_qty'    then scope.order(total_purchase_quantity: :desc)
      when 'purchase_value'  then scope.order(total_purchase_value: :desc)
      when 'sales_value'     then scope.order(total_sales_value: :desc)
      when 'inventory_value' then scope.order(current_inventory_value: :desc)
      when 'profit'          then scope.order(current_profit: :desc)
      when 'recent'          then scope.order(created_at: :desc)
      when 'oldest'          then scope.order(created_at: :asc)
      else
        scope.order(created_at: :desc)
      end
    end
  end
end