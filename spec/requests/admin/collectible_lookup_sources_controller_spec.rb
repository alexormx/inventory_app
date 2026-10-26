# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::CollectibleLookupSourcesController, type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  it 'sin guías guardadas muestra las sugeridas y el botón para guardarlas' do
    get admin_collectible_lookup_sources_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include('Guardar los sitios sugeridos').and include('mercadolibre.com.mx')
  end

  it 'guarda las sugeridas una sola vez' do
    expect { post install_defaults_admin_collectible_lookup_sources_path }
      .to change(Collectibles::LookupSource, :count).by(Collectibles::LookupSource::DEFAULTS.size)
    expect { post install_defaults_admin_collectible_lookup_sources_path }.not_to change(Collectibles::LookupSource, :count)
  end

  it 'agrega, edita y quita un sitio' do
    post admin_collectible_lookup_sources_path,
         params: { lookup_source: { name: 'Rakuten', domain: 'https://search.rakuten.co.jp/x', purpose: 'prices_world',
                                    search_url: 'https://search.rakuten.co.jp/search/mall/{q}/', active: '1' } }
    source = Collectibles::LookupSource.last
    expect(response).to redirect_to(admin_collectible_lookup_sources_path)
    expect(source.domain).to eq('search.rakuten.co.jp')

    get edit_admin_collectible_lookup_source_path(source)
    expect(response).to have_http_status(:success)

    patch admin_collectible_lookup_source_path(source), params: { lookup_source: { domain: 'rakuten.co.jp' } }
    expect(source.reload.domain).to eq('rakuten.co.jp')

    expect { delete admin_collectible_lookup_source_path(source) }.to change(Collectibles::LookupSource, :count).by(-1)
  end

  it 'un sitio inválido vuelve al formulario con el error' do
    post admin_collectible_lookup_sources_path,
         params: { lookup_source: { name: 'Malo', domain: 'ebay.com', purpose: 'prices_world', search_url: 'https://ebay.com' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('{q}')
  end

  it 'guarda los tipos de cambio y rechaza uno inválido' do
    patch rates_admin_collectible_lookup_sources_path, params: { rates: { USD: '18,40', JPY: '0.12', EUR: '' } }
    expect(SystemVariable.get('TIPO_CAMBIO_USD')).to eq('18.40')
    expect(Collectibles::PriceConversion.rates).to eq('MXN' => 1.0, 'USD' => 18.4, 'JPY' => 0.12)

    patch rates_admin_collectible_lookup_sources_path, params: { rates: { USD: 'mucho' } }
    expect(flash[:alert]).to include('USD')
    expect(SystemVariable.get('TIPO_CAMBIO_USD')).to eq('18.40')
  end

  it 'un usuario que no es admin no entra' do
    sign_out admin
    sign_in create(:user)
    get admin_collectible_lookup_sources_path
    expect(response).not_to have_http_status(:success)
  end
end
