# frozen_string_literal: true

module Shipping
  module Calculators
    class ExpressCalculator < BaseCalculator
      FLAT_FEE = 149
      def calculate(user:, address:, cart:)
        FLAT_FEE
      end
    end
  end
end
