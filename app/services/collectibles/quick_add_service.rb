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
        update_product_stats if @errors.empty?

        raise ActiveRecord::Rollback if @errors.any?
      end

      if @errors.any?
        { success: false, errors: @errors, product: @product, inventory: @inventory }
      else
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
        if @product.nil?
          @errors << 'Producto no encontrado'
        end
      else
        product_attrs = @params[:product] || {}
        @product = Product.new(product_attrs)

        # Generar SKU si no se proporciona
        if @product.product_sku.blank?
          @product.product_sku = generate_sku(@product)
        end

        unless @product.save
          @errors.concat(@product.errors.full_messages)
        end
      end
    end

    def create_inventory
      inv_attrs = @params[:inventory] || {}

      @inventory = Inventory.new(
        product: @product,
        item_condition: inv_attrs[:item_condition] || :loose,
        purchase_cost: inv_attrs[:purchase_cost].presence || 0,
        selling_price: inv_attrs[:selling_price].presence,
        notes: inv_attrs[:notes],
        inventory_location_id: inv_attrs[:inventory_location_id].presence,
        status: :available,
        status_changed_at: Time.current,
        source: 'manual'
      )

      unless @inventory.save
        @errors.concat(@inventory.errors.full_messages)
      end
    end

    def attach_images
      images = @params.dig(:inventory, :piece_images)
      return unless images.present?

      images.each do |image|
        next unless image.present?
        @inventory.piece_images.attach(image)
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
