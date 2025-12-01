# frozen_string_literal: true

module Shipping
  class Calculator
    @registry = {}

    class << self
      attr_reader :registry

      def register(key, klass)
        registry[key.to_s] = klass
      end

      def resolve(key)
        registry[key.to_s] || registry['standard']
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
