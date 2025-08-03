module Api
  module V1
    class ProductsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_admin_api!


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
            id: @product.id
            image_urls: @product.product_images.map { |img| url_for(img) }
          }, status: :created
        else
          render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def product_params
          params.permit(
            :product_name,
            :product_sku,
            :whatsapp_code,
            :barcode,
            :brand,
            :category,
            :subcategory,
            :supplier_id,
            :selling_price,
            :wholesale_price,
            :discount_limited_stock,
            :stock_quantity,
            :reserved_quantity,
            :reorder_point,
            :maximum_discount,
            :minimum_price,
            :backorder_allowed,
            :preorder_available,
            :length_cm,
            :width_cm,
            :height_cm,
            :weight_gr,
            :status,
            :description,
            product_images: []
          )
      end
    end
  end
end
