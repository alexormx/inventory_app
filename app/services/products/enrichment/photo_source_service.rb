# frozen_string_literal: true

module Products
  module Enrichment
    # Las fotos que ve la IA al describir un producto: hasta 3 de catálogo (la
    # principal primero) o, si no tiene, las de sus piezas en inventario. Una
    # foto ilegible se omite con aviso; la descripción se genera igual.
    class PhotoSourceService
      MAX_PHOTOS = 3
      Result = Struct.new(:jpegs, :warnings, keyword_init: true)

      def initialize(product)
        @product = product
      end

      def call
        jpegs = []
        warnings = []
        attachments.first(MAX_PHOTOS).each do |attachment|
          jpegs << Images::AiReadyJpeg.call(attachment)
        rescue Images::AiReadyJpeg::InvalidImage
          warnings << "No se pudo leer la foto #{attachment.filename}; se generó sin ella."
        end
        Result.new(jpegs: jpegs, warnings: warnings)
      end

      private

      def attachments
        catalog = @product.ordered_product_images
        return catalog if catalog.any?

        @product.inventories.order(:id).flat_map { |inventory| inventory.piece_images.attachments.sort_by(&:id) }
      end
    end
  end
end
