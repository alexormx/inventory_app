# frozen_string_literal: true

module Api
  # Crea o edita un producto desde la API (KataFrame) con las reglas de la
  # integración, todo o nada:
  #
  # - SKU interno generado si el producto es nuevo (Product#generate_api_sku).
  # - custom_attributes se FUSIONA con lo existente; una llave en "" o nil se borra.
  # - Fotos: solo se agregan, al final y en el orden recibido; la principal no cambia.
  # - Publicar (status "active") sigue la regla del admin (eligible_for_publication?).
  class ProductWriter
    WRITABLE = %i[product_name brand category series scale selling_price description barcode
                  launch_date status whatsapp_code length_cm width_cm height_cm weight_gr].freeze
    MAX_PHOTOS = 10
    MAX_PHOTO_BYTES = 15.megabytes
    PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze
    PUBLISH_ERROR = 'No se puede publicar: el producto no tiene existencias publicables, ni preventa ni backorder'

    Result = Data.define(:product, :errors) do
      def success?
        errors.empty?
      end
    end

    def initialize(product:, attrs:, photos:)
      @product = product
      @attrs = attrs.to_h.symbolize_keys
      @photos = Array(photos).compact_blank
    end

    def call
      errors = photo_errors
      return result(errors) if errors.any?

      creating = @product.new_record?
      Product.transaction do
        errors = assign
        raise ActiveRecord::Rollback if errors.any?

        unless @product.save
          errors = @product.errors.full_messages
          raise ActiveRecord::Rollback
        end

        @photos.each { |photo| @product.product_images.attach(photo) }
      end
      return result(errors) if errors.any?

      Products::UpdateStatsService.new(@product).call if creating
      result([])
    end

    private

    def result(errors)
      Result.new(product: @product, errors: errors)
    end

    # => errores de asignación (sin guardar)
    def assign
      @product.assign_attributes(@attrs.slice(*WRITABLE))
      merge_custom_attributes if @attrs.key?(:custom_attributes)
      @product.product_sku = @product.generate_api_sku if @product.new_record? && @product.product_sku.blank?
      # Sin precio mínimo explícito, no se permite descuento por debajo del precio de venta
      @product.minimum_price = @product.selling_price if @product.new_record? && @product.minimum_price.blank?
      publication_errors
    rescue ArgumentError => e
      # enum :status con un valor desconocido
      [e.message]
    end

    # Solo al PASAR a active: editar un producto ya activo no re-evalúa la regla
    # (de eso se encarga la auto-pausa).
    def publication_errors
      return [] unless @product.will_save_change_to_status? && @product.status == 'active'
      return [PUBLISH_ERROR] unless @product.eligible_for_publication?

      @product.auto_paused = false
      []
    end

    def merge_custom_attributes
      current = @product.custom_attributes
      current = JSON.parse(current) if current.is_a?(String)
      current = current.is_a?(Hash) ? current.stringify_keys : {}

      incoming = @attrs[:custom_attributes]
      incoming = incoming.to_unsafe_h if incoming.respond_to?(:to_unsafe_h)
      return unless incoming.is_a?(Hash)

      incoming.each do |key, value|
        if value.nil? || value == ''
          current.delete(key.to_s)
        else
          current[key.to_s] = value
        end
      end
      @product.custom_attributes = current
    rescue JSON::ParserError
      @product.custom_attributes = incoming.to_h.stringify_keys.compact_blank
    end

    def photo_errors
      return ["Máximo #{MAX_PHOTOS} fotos por petición"] if @photos.size > MAX_PHOTOS

      @photos.filter_map do |photo|
        name = photo.original_filename
        if PHOTO_TYPES.exclude?(photo.content_type.to_s)
          "La foto #{name} no es JPG, PNG ni WebP"
        elsif photo.size > MAX_PHOTO_BYTES
          "La foto #{name} pesa más de 15 MB"
        end
      end
    end
  end
end
