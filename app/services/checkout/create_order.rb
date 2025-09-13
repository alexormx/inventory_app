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

      return fail_with(['Carrito vacío']) if @cart.nil? || @cart.empty?

      source_address = @user.shipping_addresses.find_by(id: @shipping_address_id)
      return fail_with(['Dirección no encontrada']) unless source_address

      calc_cls = Shipping::Calculator.resolve(@shipping_method)
      shipping_cost = calc_cls.new.calculate(user: @user, address: source_address, cart: @cart)

      # Recalcular disponibilidad actual
      @cart.items.each do |product, qty|
        split = Inventory::AvailabilitySplitter.new(product, qty).call
        availability_map[product.id] = split
        # Caso: faltante sin permiso de preorder/backorder
        if split.pending.positive? && split.pending_type.nil?
          errors << "Producto #{product.product_name} no tiene suficiente stock y no permite preventa/backorder"
        end
      end
      return fail_with(errors) if errors.any?

      sale_order = nil
      ActiveRecord::Base.transaction do
        sale_order = @user.sale_orders.create!(
          order_date: Date.today,
          subtotal: 0,
          tax_rate: 0,
          total_tax: 0,
          shipping_cost: shipping_cost,
          total_order_value: 0,
          notes: @notes,
          status: 'Pending'
        )

        @cart.items.each do |product, qty|
          split = availability_map[product.id]
          soi = sale_order.sale_order_items.create!(
            product: product,
            quantity: qty,
            unit_cost: product.selling_price,
            total_line_cost: product.selling_price * qty,
            preorder_quantity: (split.pending_type == :preorder ? split.pending : 0),
            backordered_quantity: (split.pending_type == :backorder ? split.pending : 0)
          )
          if split.pending_type == :preorder && split.pending.positive?
            PreorderReservation.create!(
              product: product,
              user: @user,
              quantity: split.pending,
              status: :pending,
              reserved_at: Time.current,
              sale_order: nil,
              notes: "Generada desde checkout servicio SO=#{sale_order.id} SOI=#{soi.id}"
            )
          end
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
          raw_address_json: source_address.attributes.slice('id','full_name','line1','line2','city','state','postal_code','country','label','default')
        )

        sale_order.payments.create!(
          amount: 0, # se recalcula después
          payment_method: @payment_method,
          status: 'Pending'
        )

        sale_order.recalculate_totals!(persist: true)
        sale_order.payments.first.update_columns(amount: sale_order.total_order_value)
      end

      Result.new(sale_order: sale_order, errors: [], warnings: warnings, availability: availability_map)
    rescue => e
      fail_with(["Exception #{e.class}: #{e.message}"])
    end

    private

    def fail_with(errors)
      Result.new(sale_order: nil, errors: errors, warnings: [], availability: {})
    end
  end
end
