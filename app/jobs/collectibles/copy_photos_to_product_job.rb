# frozen_string_literal: true

module Collectibles
  # Copia las fotos de una pieza recién dada de alta en quick_add a su producto
  # nuevo, sin metadatos (EXIF/GPS, comentarios): las fotos de producto son
  # públicas en la tienda y una foto tomada en casa puede traer la ubicación.
  # Corre en el worker para no procesar fotos grandes en el dyno web. Un archivo
  # que no es imagen se omite: nunca llega al catálogo.
  class CopyPhotosToProductJob < ApplicationJob
    queue_as :default

    def perform(inventory_id)
      inventory = Inventory.find_by(id: inventory_id)
      return unless inventory

      product = inventory.product
      # Idempotente: en un reintento el producto ya tiene fotos y no se duplican.
      inventory.piece_images.attachments.sort_by(&:id).each { |photo| copy(photo, product) } unless product.product_images.attached?
      # Con las fotos ya copiadas, la descripción con IA puede verlas.
      Products::Enrichment::GenerateDraftJob.enqueue_for(product)
    end

    private

    def copy(photo, product)
      photo.blob.open do |file|
        # `.strip` pasa -strip a ImageMagick: quita EXIF/GPS y comentarios.
        cleaned = ImageProcessing::MiniMagick.source(file.path).strip.call
        begin
          File.open(cleaned.path) do |io|
            product.product_images.attach(io: io, filename: photo.filename.to_s, content_type: photo.content_type)
          end
        ensure
          cleaned.close!
        end
      end
    rescue MiniMagick::Error, ImageProcessing::Error => e
      Rails.logger.warn("[CopyPhotosToProductJob] se omitió #{photo.filename}: #{e.message.lines.first.to_s.strip}")
    end
  end
end
