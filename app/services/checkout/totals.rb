# frozen_string_literal: true

module Checkout
  class Totals
    CURRENCY_SCALE = 2
    ROUNDING_MODE = BigDecimal::ROUND_HALF_UP

    Result = Struct.new(
      :subtotal,
      :tax_rate,
      :tax_amount,
      :shipping_amount,
      :total,
      keyword_init: true
    )

    def initialize(cart:, shipping_method:, user:, address:)
      @cart = cart
      @shipping_method = shipping_method
      @user = user
      @address = address
    end

    def call
      subtotal = money(@cart.respond_to?(:subtotal) ? @cart.subtotal : @cart.total)
      tax_rate = current_tax_rate
      tax_amount = money(subtotal * tax_rate / 100)
      shipping_amount = money(
        Shipping::Calculator.quote(
          method_code: @shipping_method,
          user: @user,
          address: @address,
          cart: @cart
        )
      )

      Result.new(
        subtotal: subtotal,
        tax_rate: tax_rate,
        tax_amount: tax_amount,
        shipping_amount: shipping_amount,
        total: money(subtotal + tax_amount + shipping_amount)
      )
    end

    private

    def current_tax_rate
      return 0.to_d unless ActiveModel::Type::Boolean.new.cast(SiteSetting.get('tax_enabled', false))

      SiteSetting.get('tax_rate_percent', 16).to_d.round(CURRENCY_SCALE, ROUNDING_MODE)
    end

    def money(value)
      value.to_d.round(CURRENCY_SCALE, ROUNDING_MODE)
    end
  end
end
