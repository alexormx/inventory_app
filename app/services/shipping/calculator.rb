# frozen_string_literal: true

module Shipping
  class Calculator
    class UnknownMethodError < StandardError; end

    DEFAULT_FREE_SHIPPING_THRESHOLD = BigDecimal('1500').freeze

    @registry = {}

    class << self
      attr_reader :registry

      def register(key, klass)
        registry[key.to_s] = klass
      end

      def resolve(key)
        registry[key.to_s]
      end

      def free_shipping_enabled?
        ActiveModel::Type::Boolean.new.cast(SiteSetting.get('free_shipping_enabled', true))
      end

      def free_shipping_threshold
        configured_threshold = SiteSetting.get(
          'free_shipping_threshold',
          DEFAULT_FREE_SHIPPING_THRESHOLD.to_s('F')
        ).to_d

        return DEFAULT_FREE_SHIPPING_THRESHOLD unless configured_threshold.positive?

        configured_threshold.round(2, BigDecimal::ROUND_HALF_UP)
      end

      def free_shipping?(subtotal)
        free_shipping_enabled? && subtotal.to_d >= free_shipping_threshold
      end

      # The active ShippingMethod record is the checkout source of truth. This
      # keeps admin-configured codes and prices aligned with the persisted order.
      def quote(method_code:, user:, address:, cart:)
        shipping_method = ShippingMethod.active.find_by(code: method_code.to_s)
        raise UnknownMethodError, 'Método de envío no disponible.' unless shipping_method
        raise UnknownMethodError, 'Método de envío sin tarifa configurada.' if shipping_method.base_cost.nil?

        return 0.to_d if cart.respond_to?(:empty?) && cart.empty?

        subtotal = if cart.respond_to?(:subtotal)
                     cart.subtotal.to_d
                   else
                     cart.total.to_d
                   end
        return 0.to_d if free_shipping?(subtotal)

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
