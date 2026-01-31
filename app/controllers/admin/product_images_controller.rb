# frozen_string_literal: true

module Admin
  class ProductImagesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_product

    # POST /admin/products/:product_id/product_images/search
    def search
      url = params[:url]

      if url.blank?
        return render json: { success: false, error: 'URL es requerida' }, status: :unprocessable_entity
      end

      scraper = ImageScraperService.new(url)
      result = scraper.call

      if result[:success]
        render json: result, status: :ok
      else
        render json: result, status: :unprocessable_entity
      end
    end

    # POST /admin/products/:product_id/product_images/download
    def download
      image_url = params[:image_url]

      if image_url.blank?
        return render json: { success: false, error: 'URL de imagen es requerida' }, status: :unprocessable_entity
      end

      scraper = ImageScraperService.new(image_url)
      downloaded_file = scraper.download_image(image_url)

      # Attach to product
      @product.product_images.attach(
        io: downloaded_file,
        filename: File.basename(URI.parse(image_url).path),
        content_type: 'image/jpeg'
      )

      # Return the newly attached image
      attached_image = @product.product_images.last

      render json: {
        success: true,
        message: 'Imagen agregada exitosamente',
        image: {
          id: attached_image.id,
          url: url_for(attached_image),
          thumbnail: url_for(attached_image.variant(resize_to_limit: [200, 200]))
        }
      }, status: :ok

    rescue Down::NotFound => e
      render json: {
        success: false,
        error: "No se pudo descargar la imagen: #{e.message}"
      }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("Error downloading image: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: {
        success: false,
        error: "Error al procesar la imagen: #{e.message}"
      }, status: :unprocessable_entity
    end

    private

    def set_product
      @product = Product.friendly.find(params[:product_id])
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Producto no encontrado' }, status: :not_found
    end

    def authorize_admin!
      unless current_user&.admin?
        render json: { error: 'Acceso denegado' }, status: :forbidden
      end
    end
  end
end
