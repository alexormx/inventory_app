# frozen_string_literal: true

module Checkout
  class CreateOrder
    Result = Struct.new(:sale_order, :errors, :warnings, :availability, keyword_init: true) do
      def success? = errors.empty?
    end

    def initialize(user:, cart:, shipping_address_id:, shipping_method:, payment_method:, notes:, idempotency_key: nil)
      @user = user
      @cart = cart
      @shipping_address_id = shipping_address_id
      @shipping_method = shipping_method.presence || 'standard'
      @payment_method = payment_method
      @notes = notes.to_s.strip.first(1000)
      @idempotency_key = idempotency_key
      Shipping::Calculator.boot_defaults if Shipping::Calculator.respond_to?(:boot_defaults)
    end

    def call
      errors = []
      warnings = []
      availability_map = {}

      return fail_with(['Carrito vacío']) if @cart.blank?

      source_address = @user.shipping_addresses.find_by(id: @shipping_address_id)
      return fail_with(['Dirección no encontrada']) unless source_address

      calc_cls = Shipping::Calculator.resolve(@shipping_method)
      shipping_cost = calc_cls.new.calculate(user: @user, address: source_address, cart: @cart)

      # Recalcular disponibilidad actual (nuevo formato: items es array de hashes)
      @cart.items.each do |item|
        product = item[:product]
        qty = item[:quantity]
        condition = item[:condition]

        # Para coleccionables, validar disponibilidad específica por condición
        if condition != 'brand_new'
          available = product.inventories.where(status: :available, item_condition: condition).count
          if qty > available
            errors << "#{product.product_name} (#{item[:label]}) no tiene suficiente stock (disponible: #{available})"
          end
        else
          split = InventoryServices::AvailabilitySplitter.new(product, qty).call
          availability_map["#{product.id}_#{condition}"] = split
          if split.pending.positive? && split.pending_type.nil?
            errors << "Producto #{product.product_name} no tiene suficiente stock y no permite preventa/backorder"
          end
        end
      end
      return fail_with(errors) if errors.any?

      # Segunda etapa: antes de crear la orden, revalidamos con bloqueo pesimista
      # para evitar condiciones de carrera entre múltiples checkouts.
      # Bloqueamos los productos involucrados para la duración de la transacción.
      sale_order = nil
      revalidation_errors = []

      # Evitar que Bullet interrumpa transacciones críticas del checkout
      previous_bullet_state = nil
      if defined?(Bullet)
        previous_bullet_state = Bullet.enabled?
        Bullet.enable = false
      end
      ActiveRecord::Base.transaction do
        # @cart.items ahora es array de hashes con :product, :condition, :quantity, :price, etc.
        product_ids = @cart.items.map { |item| item[:product].id }.uniq
        # Cargamos y bloqueamos filas de producto (SELECT ... FOR UPDATE)
        locked_products = Product.where(id: product_ids).lock.order(:id).to_a
        locked_products_map = locked_products.index_by(&:id)

        # Recalcular disponibilidad sobre los productos bloqueados
        revalidated = {}
        @cart.items.each do |item|
          product = item[:product]
          qty = item[:quantity]
          condition = item[:condition]
          key = "#{product.id}_#{condition}"

          # Usar el producto bloqueado
          locked_product = locked_products_map[product.id]
          unless locked_product
            revalidation_errors << "Producto #{product.product_name} no encontrado durante revalidación"
            next
          end

          if condition != 'brand_new'
            # Para coleccionables, validar disponibilidad específica
            available = locked_product.inventories.where(status: :available, item_condition: condition).count
            if qty > available
              revalidation_errors << "#{locked_product.product_name} (#{item[:label]}) ya no está disponible"
            end
            revalidated[key] = { collectible: true, available: available }
          else
            split = InventoryServices::AvailabilitySplitter.new(locked_product, qty).call
            revalidated[key] = split

            if split.pending.positive? && split.pending_type.nil?
              revalidation_errors << "Producto #{locked_product.product_name} quedó sin stock suficiente durante el checkout (disponible: #{split.immediate}, solicitado: #{qty})"
            end
          end
        end

        # Si hay errores de revalidación, hacemos rollback y retornamos
        raise ActiveRecord::Rollback if revalidation_errors.any?

        sale_order = @user.sale_orders.create!(
          order_date: Time.zone.today,
          subtotal: 0,
          tax_rate: 0,
          total_tax: 0,
          shipping_cost: shipping_cost,
          total_order_value: 0,
          notes: @notes,
          status: 'Pending',
          idempotency_key: @idempotency_key
        )

        @cart.items.each do |item|
          product = item[:product]
          qty = item[:quantity]
          condition = item[:condition]
          item_price = item[:price]
          key = "#{product.id}_#{condition}"

          revalidation_data = revalidated[key] || availability_map[key]

          # Determinar preorder/backorder (solo para brand_new)
          preorder_qty = 0
          backorder_qty = 0
          if condition == 'brand_new' && revalidation_data.respond_to?(:pending_type)
            preorder_qty = revalidation_data.pending_type == :preorder ? revalidation_data.pending : 0
            backorder_qty = revalidation_data.pending_type == :backorder ? revalidation_data.pending : 0
          end

          soi = sale_order.sale_order_items.create!(
            product: product,
            quantity: qty,
            unit_cost: item_price,
            unit_selling_price: item_price,
            total_line_cost: item_price * qty,
            item_condition: condition,
            preorder_quantity: preorder_qty,
            backordered_quantity: backorder_qty
          )

          # Crear reservación de preorder si aplica
          next unless preorder_qty.positive?

          PreorderReservation.create!(
            product: product,
            user: @user,
            quantity: preorder_qty,
            status: :pending,
            reserved_at: Time.current,
            sale_order: nil,
            notes: "Generada desde checkout servicio SO=#{sale_order.id} SOI=#{soi.id}"
          )
        end

        # Snapshot dirección
        OrderShippingAddress.create!(
          sale_order: sale_order,
          source_shipping_address_id: source_address.id,
          full_name: source_address.full_name,
          line1: source_address.line1,
          line2: source_address.line2,
          city: source_address.city,
          state: source_address.state,
          postal_code: source_address.postal_code,
          country: source_address.country,
          shipping_method: @shipping_method,
          raw_address_json: source_address.attributes.slice('id', 'full_name', 'line1', 'line2', 'city', 'state', 'postal_code', 'country', 'label', 'default')
        )
        # Recalcular totales ahora que ya tenemos líneas y snapshot
        sale_order.recalculate_totals!(persist: true)
      end
      # Restaurar estado de Bullet
      Bullet.enable = previous_bullet_state if defined?(Bullet) && !previous_bullet_state.nil?

      # Si hubo errores de revalidación después del rollback, retornarlos
      return fail_with(revalidation_errors) if revalidation_errors.any?

      # Crear pago fuera de la transacción para evitar abortos por callbacks
      begin
        if sale_order && sale_order.total_order_value.to_f.positive?
          sale_order.payments.create!(
            amount: sale_order.total_order_value,
            payment_method: @payment_method,
            status: 'Pending'
          )
        end
      rescue StandardError => e
        Rails.logger.error "[Checkout::CreateOrder] Payment create error: #{e.class}: #{e.message}"
      end

      # Backfill suave: asegurar sale_order_item_id en inventarios reservados de esta orden
      begin
        if sale_order
          sale_order.sale_order_items.find_each do |soi|
            Inventory.where(sale_order_id: sale_order.id, product_id: soi.product_id, sale_order_item_id: nil)
                     .update_all(sale_order_item_id: soi.id, updated_at: Time.current)
          end
        end
      rescue StandardError => e
        Rails.logger.error "[Checkout::CreateOrder] Soft backfill error: #{e.class}: #{e.message}"
      end

      Result.new(sale_order: sale_order, errors: [], warnings: warnings, availability: availability_map)
    rescue StandardError => e
      Rails.logger.error "[Checkout::CreateOrder] ERROR #{e.class}: #{e.message}"
      Array(e.backtrace).first(20).each { |ln| Rails.logger.error "[Checkout::CreateOrder] \t#{ln}" }
      Rails.logger.error "[Checkout::CreateOrder] SaleOrder errors: #{sale_order.errors.full_messages.join('; ')}" if sale_order&.errors&.any?
      raise
    end

    private

    def fail_with(errors)
      Result.new(sale_order: nil, errors: errors, warnings: [], availability: {})
    end
  end
end
