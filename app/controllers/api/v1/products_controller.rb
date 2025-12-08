# frozen_string_literal: true

module Api
  module V1
    class ProductsController < ApplicationController
      include CustomAttributesParam
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!
      before_action :fix_custom_attributes_param, only: %i[create]

      def create
        @product = Product.new(product_params.except(:product_images))

        if @product.save
          # Attach images if provided
          if params[:product][:product_images].present?
            params[:product][:product_images].each do |image|
              @product.product_images.attach(image)
            end
          end

          Products::UpdateStatsService.new(@product).call

          render json: {
            message: 'Product created',
            id: @product.id,
            image_urls: @product.product_images.map { |img| url_for(img) }
          }, status: :created
        else
          render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def exists
        ws_code = params[:whatsapp_code].to_s.strip
        exists = Product.exists?(whatsapp_code: ws_code)
        render json: { exists: exists }, status: :ok
      end

      private

      def fix_custom_attributes_param
        return if params[:product].blank?

        coerce_custom_attributes!(params[:product]) # <- del concern
      end

      def product_params
        params.expect(
          product: [:product_name,
                    :product_sku,
                    :whatsapp_code,
                    :barcode,
                    :brand,
                    :category,
                    :selling_price,
                    :maximum_discount,
                    :minimum_price,
                    :length_cm,
                    :width_cm,
                    :height_cm,
                    :weight_gr,
                    :description,
                    :supplier_product_code,
                    { custom_attributes: {},
                      product_images: [] }]
        )
      end
    end
  end
end
