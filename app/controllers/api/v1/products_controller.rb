class Api::V1::ProductsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  def create
    @product = Product.new(product_params.except(:product_images))

    # Attach images if provided
    if params[:product_images].present?
      params[:product_images].each do |image|
        @product.product_images.attach(image)
      end
    end

    if @product.save
      Products::UpdateStatsService.new(@product).call

      render json: {
        message: "Product created",
        id: @product.id,
        image_urls: @product.product_images.map { |img| url_for(img) }
      }, status: :created
    else
      render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def authenticate_with_token!
    token = request.headers["Authorization"].to_s.split(" ").last
    user = User.find_by(api_token: token)

    if user&.admin?
      @current_user = user
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end


  def product_params
      params.require(:product).permit(
        :product_name,
        :product_sku,
        :whatsapp_code,
        :barcode,
        :brand,
        :category,
        :subcategory,
        :selling_price,
        :wholesale_price,
        :maximum_discount,
        :minimum_price,
        :length_cm,
        :width_cm,
        :height_cm,
        :weight_gr,
        :description,
        :supplier_product_code,
        product_images: []
      )
  end

end
