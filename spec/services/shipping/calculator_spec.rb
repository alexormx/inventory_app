# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shipping::Calculator do
  let(:user) { create(:user) }
  let(:address) { create(:shipping_address, user: user) }
  let(:cart) { instance_double(Cart, empty?: false, subtotal: 500.to_d, total: 500.to_d) }

  describe '.quote' do
    it 'uses the configured base cost for a production shipping code' do
      create(:shipping_method, code: 'envio_estandar', base_cost: 99.00, active: true)

      quote = described_class.quote(
        method_code: 'envio_estandar', user: user, address: address, cart: cart
      )

      expect(quote).to eq(99.to_d)
    end

    it 'keeps configured pickup free' do
      create(:shipping_method, code: 'recoger_tienda', base_cost: 0, active: true)

      quote = described_class.quote(
        method_code: 'recoger_tienda', user: user, address: address, cart: cart
      )

      expect(quote).to eq(0.to_d)
    end

    it 'applies the established free-shipping threshold to a chargeable method' do
      create(:shipping_method, code: 'envio_estandar', base_cost: 99.00, active: true)
      eligible_cart = instance_double(Cart, empty?: false, subtotal: 1_500.to_d, total: 1_500.to_d)

      quote = described_class.quote(
        method_code: 'envio_estandar', user: user, address: address, cart: eligible_cart
      )

      expect(quote).to eq(0.to_d)
    end

    it 'fails closed for an inactive or unknown method instead of returning free shipping' do
      create(:shipping_method, code: 'envio_inactivo', base_cost: 99.00, active: false)

      expect do
        described_class.quote(
          method_code: 'envio_inactivo', user: user, address: address, cart: cart
        )
      end.to raise_error(Shipping::Calculator::UnknownMethodError)
    end
  end
end
