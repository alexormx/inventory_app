# frozen_string_literal: true

module Shipping
  class Calculator
    class UnknownMethodError < StandardError; end

    @registry = {}

    class << self
      attr_reader :registry

      def register(key, klass)
        registry[key.to_s] = klass
      end

      def resolve(key)
        registry[key.to_s]
      end

      # The active ShippingMethod record is the checkout source of truth. This
      # keeps admin-configured codes and prices aligned with the persisted order.
      def quote(method_code:, user:, address:, cart:)
        shipping_method = ShippingMethod.active.find_by(code: method_code.to_s)
        raise UnknownMethodError, 'Método de envío no disponible.' unless shipping_method

        return 0.to_d if cart.respond_to?(:empty?) && cart.empty?

        subtotal = if cart.respond_to?(:subtotal)
                     cart.subtotal.to_d
                   else
                     cart.total.to_d
                   end
        return 0.to_d if subtotal >= Cart::FREE_SHIPPING_THRESHOLD.to_d

        shipping_method.base_cost.to_d.round(2)
      end

      # Eager register defaults (safe if loaded multiple veces)
      def boot_defaults
        register('standard', Shipping::Calculators::StandardCalculator) unless registry.key?('standard')
        register('express',  Shipping::Calculators::ExpressCalculator)  unless registry.key?('express')
        register('pickup',   Shipping::Calculators::PickupCalculator)   unless registry.key?('pickup')
      end
    end
  end
end
