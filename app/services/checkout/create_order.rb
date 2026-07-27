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
    end

    def call
      errors = []
      warnings = []
      availability_map = {}

      return fail_with(['Carrito vacío']) if @cart.blank?

      source_address = @user.shipping_addresses.find_by(id: @shipping_address_id)
      return fail_with(['Dirección no encontrada']) unless source_address

      totals = Checkout::Totals.new(
        cart: @cart,
        shipping_method: @shipping_method,
        user: @user,
        address: source_address
      ).call
      shipping_method_name = ShippingMethod.find_by(code: @shipping_method)&.name || @shipping_method.to_s.humanize

      # Recalcular disponibilidad actual (nuevo formato: items es array de hashes)
      @cart.items.each do |item|
        product = item[:product]
        qty = item[:quantity]
        condition = item[:condition]

        split = InventoryServices::AvailabilitySplitter.new(product, qty, condition: condition).call
        availability_map["#{product.id}_#{condition}"] = split
        if split.pending.positive? && split.pending_type.nil?
          if condition == 'brand_new'
            errors << "Producto #{product.product_name} no tiene suficiente stock y no permite preventa/backorder"
          else
            available = split.immediate + split.in_transit_qty
            errors << "#{product.product_name} (#{item[:label]}) no tiene suficiente stock (disponible: #{available})"
          end
        end
      end
      return fail_with(errors) if errors.any?

      # Segunda etapa: antes de crear la orden, revalidamos con bloqueo pesimista
      # para evitar condiciones de carrera entre múltiples checkouts.
      # Bloqueamos los productos involucrados para la duración de la transacción.
      sale_order = nil
      revalidation_errors = []

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

          split = InventoryServices::AvailabilitySplitter.new(
            locked_product,
            qty,
            condition: condition
          ).call
          revalidated[key] = split

          if split.pending.positive? && split.pending_type.nil?
            if condition == 'brand_new'
              revalidation_errors << "Producto #{locked_product.product_name} quedó sin stock suficiente durante el checkout (disponible: #{split.immediate}, solicitado: #{qty})"
            else
              revalidation_errors << "#{locked_product.product_name} (#{item[:label]}) ya no está disponible"
            end
          end
        end

        # Si hay errores de revalidación, hacemos rollback y retornamos
        raise ActiveRecord::Rollback if revalidation_errors.any?

        sale_order = @user.sale_orders.create!(
          order_date: Time.zone.today,
          subtotal: totals.subtotal,
          tax_rate: totals.tax_rate,
          total_tax: totals.tax_amount,
          shipping_cost: totals.shipping_amount,
          total_order_value: totals.total,
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
            unit_cost: product.average_purchase_cost.to_d,
            unit_selling_price: item_price.to_d,
            unit_final_price: item_price.to_d,
            total_line_cost: item_price.to_d * qty,
            item_condition: condition,
            preorder_quantity: preorder_qty,
            backordered_quantity: backorder_qty
          )
          InventoryServices::ReserveSaleOrderItem.call(soi)

          # Crear reservación de preorder si aplica
          next unless preorder_qty.positive?

          PreorderReservation.create!(
            product: product,
            user: @user,
            quantity: preorder_qty,
            status: :pending,
            reserved_at: Time.current,
            sale_order: sale_order,
            sale_order_item: soi,
            notes: 'Generada desde checkout'
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
          raw_address_json: source_address.attributes
                                          .slice('id', 'full_name', 'line1', 'line2', 'city', 'state', 'postal_code', 'country', 'label', 'default')
                                          .merge('shipping_method_name' => shipping_method_name)
        )
        # Recalcular totales ahora que ya tenemos líneas y snapshot
        sale_order.recalculate_totals!(persist: true)

        if sale_order.total_order_value.to_d.positive?
          sale_order.payments.create!(
            amount: sale_order.total_order_value,
            payment_method: @payment_method,
            status: 'Pending'
          )
        end
      end

      # Si hubo errores de revalidación después del rollback, retornarlos
      return fail_with(revalidation_errors) if revalidation_errors.any?

      Result.new(sale_order: sale_order, errors: [], warnings: warnings, availability: availability_map)
    rescue InventoryServices::ReserveSaleOrderItem::InsufficientInventory => e
      fail_with([e.message])
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
