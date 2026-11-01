# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CheckoutsHelper, type: :helper do
  def brand_for(**attrs)
    helper.payment_method_brand(PaymentMethod.new({ name: 'X', code: 'efectivo' }.merge(attrs))).key
  end

  it 'recognizes each payment brand by code, name or bank' do
    expect(brand_for(code: 'transferencia_bancaria', name: 'Transferencia', bank_name: 'BBVA')).to eq('bbva')
    expect(brand_for(code: 'mercado_pago', name: 'Pago en línea')).to eq('mercado-pago')
    expect(brand_for(name: 'Spin by OXXO')).to eq('spin')
    expect(brand_for(name: 'Depósito en OXXO')).to eq('spin')
    expect(brand_for(name: 'Efectivo en tienda')).to eq('default')
  end
end
