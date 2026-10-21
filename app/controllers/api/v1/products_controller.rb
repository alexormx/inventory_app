# frozen_string_literal: true

module Api
  module V1
    class ProductsController < ApplicationController
      include CustomAttributesParam
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!
      before_action :fix_custom_attributes_param, only: %i[create update]
      before_action -> { require_scope!('products:read') }, only: %i[index show]
      before_action :require_write_scopes!, only: %i[create update], unless: :legacy_token?

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
        return legacy_create if legacy_token?

        write(Product.new, success_status: :created)
      end

      # Solo cambia lo que viene; las fotos se agregan al final.
      def update
        product = Product.find_by(id: params[:id])
        return render json: { error: 'Not found' }, status: :not_found unless product

        write(product, success_status: :ok)
      end

      def exists
        ws_code = params[:whatsapp_code].to_s.strip.upcase
        exists = Product.exists?(whatsapp_code: ws_code)
        render json: { exists: exists }, status: :ok
      end

      private

      # Contrato original de create para el token legado (scripts existentes):
      # mismos parámetros (incluye product_sku/supplier_product_code) y respuesta.
      def legacy_create
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

      def write(product, success_status:)
        result = Api::ProductWriter.new(product: product, attrs: write_attrs, photos: write_photos).call
        if result.success?
          render_product(result.product.reload, status: success_status)
        else
          render json: { errors: result.errors }, status: :unprocessable_entity
        end
      end

      # Con clave: products:write si trae campos, photos:write si trae fotos.
      def require_write_scopes!
        require_scope!('products:write') if write_attrs.present? || action_name == 'create'
        require_scope!('photos:write') if !performed? && write_photos.any?
      end

      # `params.fetch` (no `expect`): una petición solo con fotos, o vacía, es válida.
      def write_product_params
        raw = params.fetch(:product, {})
        raw.is_a?(ActionController::Parameters) ? raw : ActionController::Parameters.new
      end

      def write_attrs
        @write_attrs ||= write_product_params.permit(*Api::ProductWriter::WRITABLE, custom_attributes: {}).to_h
      end

      def write_photos
        @write_photos ||= Array(write_product_params[:product_images]).select { |file| file.respond_to?(:original_filename) }
      end

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
