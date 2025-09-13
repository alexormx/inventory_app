module Shipping
  module Calculators
    class BaseCalculator
      def calculate(user:, address:, cart:)
        raise NotImplementedError
      end
    end
  end
end
