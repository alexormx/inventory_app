# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin settings', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    SiteSetting.delete_all
    sign_in admin
  end

  it 'renders the current free-shipping controls for an administrator' do
    SiteSetting.set('free_shipping_enabled', false, 'boolean')
    SiteSetting.set('free_shipping_threshold', '1750.00', 'string')

    get admin_settings_path

    document = Nokogiri::HTML5(response.body)
    rendered_settings = {
      status: response.status,
      enabled: document.at_css('#free_shipping_enabled option[selected]')&.[]('value'),
      threshold: document.at_css('#free_shipping_threshold')&.[]('value')
    }
    expect(rendered_settings).to eq(status: 200, enabled: 'false', threshold: '1750.0')
  end

  it 'persists whether free shipping is enabled and its minimum subtotal' do
    post admin_settings_path, params: {
      save_free_shipping: '1',
      free_shipping_enabled: 'true',
      free_shipping_threshold: '1850.50'
    }

    expect(response).to redirect_to(admin_settings_path)
    expect(SiteSetting.get('free_shipping_enabled')).to be(true)
    expect(SiteSetting.get('free_shipping_threshold').to_d).to eq(1_850.50.to_d)
    expect(flash[:notice]).to eq('Configuración de envío gratis guardada.')
  end

  it 'allows an administrator to disable the promotion' do
    post admin_settings_path, params: {
      save_free_shipping: '1',
      free_shipping_enabled: 'false',
      free_shipping_threshold: '1500.00'
    }

    expect(SiteSetting.get('free_shipping_enabled')).to be(false)
  end

  it 'rejects a non-positive free-shipping threshold' do
    post admin_settings_path, params: {
      save_free_shipping: '1',
      free_shipping_enabled: 'true',
      free_shipping_threshold: '0'
    }

    expect(response).to redirect_to(admin_settings_path)
    expect(SiteSetting.get('free_shipping_enabled')).to be_nil
    expect(flash[:alert]).to eq('El monto mínimo para envío gratis debe ser mayor a cero.')
  end
end
