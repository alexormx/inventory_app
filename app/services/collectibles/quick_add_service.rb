# frozen_string_literal: true

module Collectibles
  class QuickAddService
    def initialize(params:, user:)
      @params = params
      @user = user
      @product = nil
      @inventory = nil
      @errors = []
    end

    def call
      ActiveRecord::Base.transaction do
        find_or_create_product
        create_inventory if @errors.empty?
        attach_images if @errors.empty? && @inventory&.persisted?
        link_ai_lookup if @errors.empty?
        update_product_stats if @errors.empty?

        raise ActiveRecord::Rollback if @errors.any?
      end

      if @errors.any?
        { success: false, errors: @errors, product: @product, inventory: @inventory }
      else
        enqueue_follow_up_jobs
        {
          success: true,
          message: "Coleccionable agregado: #{@product.product_name} (#{@inventory.condition_label})",
          product: @product,
          inventory: @inventory
        }
      end
    end

    private

    def find_or_create_product
      if @params[:use_existing_product] == '1' && @params[:existing_product_id].present?
        @product = Product.find_by(id: @params[:existing_product_id])
        @errors << 'Producto no encontrado' if @product.nil?
      else
        product_attrs = @params[:product] || {}
        @product = Product.new(product_attrs)

        # Generar SKU si no se proporciona
        @product.product_sku = generate_sku(@product) if @product.product_sku.blank?

        # Defaults requeridos por Product que el form de quick_add no expone
        @product.maximum_discount ||= 0
        @product.minimum_price    ||= @product.selling_price

        @product_created = @product.save
        @errors.concat(@product.errors.full_messages) unless @product_created
      end
    end

    def create_inventory
      inv_attrs = @params[:inventory] || {}

      @inventory = Inventory.new(
        product: @product,
        item_condition: inv_attrs[:item_condition] || :loose,
        purchase_cost: inv_attrs[:purchase_cost].presence || 0,
        selling_price: inv_attrs[:selling_price].presence,
        purchase_date: inv_attrs[:purchase_date].presence || Date.current,
        notes: inv_attrs[:notes],
        inventory_location_id: inv_attrs[:inventory_location_id].presence,
        status: :available,
        status_changed_at: Time.current,
        source: 'manual'
      )

      return if @inventory.save

      @errors.concat(@inventory.errors.full_messages)
    end

    # Las fotos son de la pieza; la vista 3/4 llega en su propio campo y va
    # primero. Si este alta creó el producto y hay vista 3/4, las fotos también
    # se vuelven sus fotos de catálogo (la 3/4 queda como principal): las copia
    # CopyPhotosToProductJob, sin metadatos, en el worker. Sin 3/4 no se copian,
    # para que la foto principal de la tienda nunca sea la base o un detalle.
    # Un producto existente no se toca.
    def attach_images
      three_quarter = @params.dig(:inventory, :three_quarter_image).presence
      images = ([three_quarter] + Array(@params.dig(:inventory, :piece_images))).compact_blank
      return if images.empty?

      images.each { |image| @inventory.piece_images.attach(image) }
      @copy_photos_to_product = @product_created && three_quarter.present?
    end

    # Si el admin identificó la pieza con IA antes de dar de alta un producto
    # nuevo, la búsqueda queda ligada a él: la descripción con IA la usa como
    # datos confirmados. Sólo una búsqueda terminada, del mismo admin y con
    # identificación confiable: si la IA dudó, sus datos podrían ser de otra pieza.
    def link_ai_lookup
      return unless @product_created && @params[:ai_lookup_id].present?

      lookup = Collectibles::AiLookup.where(user: @user, status: :done).find_by(id: @params[:ai_lookup_id])
      lookup.update!(product: @product) if lookup&.confident?
    end

    # Después del commit, para que el worker encuentre la pieza y sus fotos. Un
    # producto nuevo recibe su borrador de descripción con IA (para revisión,
    # nunca se publica solo); si hay fotos que copiarle, el borrador lo encola
    # la copia al terminar, para que la IA las vea.
    def enqueue_follow_up_jobs
      return unless @product_created

      if @copy_photos_to_product
        Collectibles::CopyPhotosToProductJob.perform_later(@inventory.id)
      else
        Products::Enrichment::GenerateDraftJob.enqueue_for(@product)
      end
    end

    def update_product_stats
      Products::UpdateStatsService.new(@product).call
    rescue StandardError => e
      Rails.logger.warn "[QuickAddService] Error updating stats: #{e.message}"
    end

    def generate_sku(product)
      prefix = 'COL'
      category_code = product.category.to_s.first(3).upcase.presence || 'XXX'
      timestamp = Time.current.strftime('%y%m%d%H%M%S')
      "#{prefix}#{category_code}#{timestamp}"
    end
  end
end
