# frozen_string_literal: true

module Api
  module V1
    class ProductsController < ApplicationController
      include CustomAttributesParam
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!
      before_action :fix_custom_attributes_param, only: %i[create]
      before_action -> { require_scope!('products:read') }, only: %i[index show]

      PER_PAGE = 100

      # Todos los productos (borradores, inactivos y agotados incluidos: se
      # fotografían antes de publicar). KataFrame sigue `next` hasta que falta.
      def index
        scope = Product.order(:id)
        if params[:updated_since].present?
          since = parse_time(params[:updated_since])
          return render json: { errors: ['updated_since no es una fecha ISO 8601 válida'] }, status: :unprocessable_entity unless since

          scope = scope.where(updated_at: since..)
        end

        page = scope.with_attached_product_images.page(params[:page]).per(self.class::PER_PAGE)
        products = page.to_a
        stock = ProductSerializer.stock_by_product(products.map(&:id))
        body = { items: products.map { |product| serialize(product, stock.fetch(product.id, 0)) } }
        body[:next] = url_for(request.query_parameters.merge(page: page.next_page, only_path: false)) if products.any? && page.next_page
        render json: body
      end

      def show
        product = Product.find_by(id: params[:id])
        return render json: { error: 'Not found' }, status: :not_found unless product

        render_product(product)
      end

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
        ws_code = params[:whatsapp_code].to_s.strip.upcase
        exists = Product.exists?(whatsapp_code: ws_code)
        render json: { exists: exists }, status: :ok
      end

      private

      def render_product(product, status: :ok)
        stock = ProductSerializer.stock_by_product([product.id]).fetch(product.id, 0)
        render json: serialize(product, stock), status: status
      end

      def serialize(product, stock)
        ProductSerializer.new(product, url_builder: self, stock_available: stock).as_json
      end

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

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
