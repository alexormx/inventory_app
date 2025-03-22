class Admin::ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

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
      render :new
    end
  end

  def edit
    @product = Product.find(params[:id])
  end

  def update
    @product = Product.find(params[:id])
    if @product.update(product_params)
      flash[:notice] = "Product updated successfully."
      redirect_to admin_product_path(@product)
    else
      flash.now[:alert] = "Error updating product."
      render :edit
    end
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
      :product_description,
      :selling_price,
      :maximum_discount,
      :minimum_price,
      :discount_limited_stock,
      :backorder_allowed,
      :preorder_available,
      :status,
      :product_images,
      :custom_attributes,
      :supplier_id
    )
  end
end