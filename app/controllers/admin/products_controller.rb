class Admin::ProductsController < ApplicationController
  include CustomAttributesParam
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_product, only: %i[show edit update destroy purge_image activate deactivate]
  before_action :fix_custom_attributes_param, only: [:create, :update]
  before_action :load_counts, only: [:index, :drafts, :active, :inactive]

  # Tamaño de página para listados en este controlador (cambiar aquí para afectar todas las vistas)
  PER_PAGE = 9

  def index
    @q = params[:q].to_s.strip
    current_status = params[:status].presence || 'all'
    scope = Product.all
    if current_status != 'all'
      scope = scope.where(status: current_status)
    end
    if @q.present?
      term = "%#{@q.downcase}%"
      scope = scope.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term)
    end
  @products = scope.order(created_at: :desc).page(params[:page]).per(PER_PAGE)
  compute_counts
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)
    if @product.save
      flash[:notice] = "Product created successfully."
      redirect_to admin_products_path
    else
      flash.now[:alert] = "Error creating product."
      render :new
    end
  end

  def edit

  end

  def update

    if params[:product][:product_images]
      # Attach new images *without removing existing ones*
      params[:product][:product_images].each do |image|
        @product.product_images.attach(image)
      end
    end

    if @product.update(product_params.except(:product_images))
      flash[:notice] = "Product updated successfully."
      redirect_to admin_product_path(@product)
    else
      flash.now[:alert] = "Error updating product."
      render :edit
    end
  end

  def show

  end

  def destroy

    if @product.destroy
      flash[:notice] = "Product deleted successfully."
      redirect_to admin_products_path
    else
      flash[:alert] = "Error deleting product."
      redirect_to admin_product_path(@product)
    end
  end

  def purge_image
    image = @product.product_images.find(params[:image_id])
    image_id = image.id
    image.purge # or purge_later for async

    respond_to do |format|
      format.html { redirect_to edit_admin_product_path(@product), notice: "Image removed successfully." }
      format.turbo_stream { render turbo_stream: turbo_stream.remove("image_#{image_id}")}# optional: for dynamic deletion
    end
  end

  def search
    q = params[:query].to_s.strip
    return render json: [] if q.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"

    products = Product
      .includes(product_images_attachments: :blob) # avoids N+1 when calling variant
      .where(
        "LOWER(product_name) LIKE LOWER(?) OR LOWER(product_sku) LIKE LOWER(?)",
        pattern, pattern
      )
      .order(:product_name)
      .limit(20)

    render json: products.map { |product|
      thumb_url =
        if product.product_images.attached?
          url_for(product.product_images.first.variant(resize_to_limit: [40, 40]).processed)
        else
          helpers.asset_path("placeholder.png")
        end

      {
        id: product.id,
        product_name: product.product_name,
        product_sku: product.product_sku,
        weight_gr: product.weight_gr,
        length_cm: product.length_cm,
        width_cm: product.width_cm,
        height_cm: product.height_cm,
        thumbnail_url: thumb_url
      }
    }
  end

  def activate

  @product.update(status: "active")

    respond_to do |format|
      format.turbo_stream do
        source_tab = params[:source_tab].presence || 'active'
        @products = Product.where(status: source_tab).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
        load_counts
      end
      format.html { redirect_to admin_products_path, notice: "Product activated" }
    end
  end


  def deactivate
    @product.update(status: "inactive")
    respond_to do |format|
      format.turbo_stream do
        source_tab = params[:source_tab].presence || 'inactive'
        @products = Product.where(status: source_tab).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
        load_counts
      end
      format.html { redirect_to admin_products_path, notice: "Product deactivated" }
    end
  end

  # --- Vistas por estado ---
  def drafts
    @q = params[:q].to_s.strip
    scope = Product.where(status: 'draft')
    if @q.present?
      term = "%#{@q.downcase}%"
      scope = scope.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term)
    end
  @products = scope.order(created_at: :desc).page(params[:page]).per(PER_PAGE)
  compute_counts
  render :drafts, layout: false
  end

  def active
    @q = params[:q].to_s.strip
    scope = Product.where(status: 'active')
    if @q.present?
      term = "%#{@q.downcase}%"
      scope = scope.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term)
    end
  @products = scope.order(created_at: :desc).page(params[:page]).per(PER_PAGE)
  compute_counts
  render :active, layout: false
  end

  def inactive
    @q = params[:q].to_s.strip
    scope = Product.where(status: 'inactive')
    if @q.present?
      term = "%#{@q.downcase}%"
      scope = scope.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term)
    end
  @products = scope.order(created_at: :desc).page(params[:page]).per(PER_PAGE)
  compute_counts
  render :inactive, layout: false
  end


  private

  def load_counts
    compute_counts unless defined?(@counts_global)
  end

  def compute_counts
    q = params[:q].to_s.strip
    base = Product.all
    if q.present?
      term = "%#{q.downcase}%"
      base = base.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term)
    end
    # Aplicar también el filtro de status actual para los contadores inferiores
    current_status = params[:status].presence || 'all'
    filtered_base = base
    if current_status != 'all'
      filtered_base = filtered_base.where(status: current_status)
    end
    # Globales (no dependen de q)
    @counts_global = {
      draft:   Product.where(status: 'draft').count,
      active:  Product.where(status: 'active').count,
      inactive: Product.where(status: 'inactive').count
    }
    # Inferiores (dependen de q)
    @counts = {
      draft:   filtered_base.where(status: 'draft').count,
      active:  filtered_base.where(status: 'active').count,
      inactive: filtered_base.where(status: 'inactive').count
    }
  end

  def fix_custom_attributes_param
    return unless params[:product].present?
    coerce_custom_attributes!(params[:product])  # <- del concern
  end
  # Strong parameters for product
  def product_params
    params.require(:product).permit(
      :product_sku,
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
      custom_attributes: {}, # allow custom attributes as a hash
      product_images: [] # allow multiple file uploads
    )

  end

  def set_product
    id = params[:id] || params[:product_id]
    begin
      @product = Product.friendly.find(id)
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to admin_products_path, alert: "Product not found." }
        format.json { render json: { error: "Product not found" }, status: :not_found }
      end
    end
  end
end