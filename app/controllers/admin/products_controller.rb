class Admin::ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_product, only: %i[show edit update destroy purge_image]

  def index
    @products = Product.all
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
      puts @product.errors.full_messages.inspect # 👈 Add this line
      render :new
    end
  end

  def edit
    @product = Product.find(params[:id])
  end

  def update
    @product = Product.find(params[:id])

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
    @product = Product.find(params[:id])
  end
  
  def destroy
    @product = Product.find(params[:id])
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
    @products = Product.where("product_name ILIKE ? OR product_sku ILIKE ?", "%#{params[:query]}%", "%#{params[:query]}%")

    render json: @products.map { |product|
      {
        id: product.id,
        product_name: product.product_name,
        product_sku: product.product_sku,
        weight_gr: product.weight_gr,
        length_cm: product.length_cm,
        width_cm: product.width_cm,
        height_cm: product.height_cm,
        thumbnail_url: product.product_images.attached? ?
          url_for(product.product_images.first.variant(resize_to_limit: [40, 40])) :
          ActionController::Base.helpers.asset_path("placeholder.png") # fallback
      }
    }
  end


  private
  # Strong parameters for product
  def product_params
    params.require(:product).permit(
      :product_sku,
      :barcode,
      :brand,
      :category,
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
      :custom_attributes,
      :supplier_id,
      :weight_gr, 
      :length_cm,
      :width_cm,
      :height_cm,
      product_images: [] # allow multiple file uploads
    )
  end

  def set_product
    @product = Product.find_by(id: params[:id]) || Product.find_by(id: params[:product_id])

    unless @product
      respond_to do |format|
        format.html { redirect_to admin_products_path, alert: "Product not found." }
        format.json { render json: { error: "Product not found" }, status: :not_found }
      end
    end
  end
end