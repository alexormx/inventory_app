require 'rails_helper'
RSpec.describe 'API Postal Codes', type: :request do
  before do
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'centro')
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'modulo i')
  end

  it 'retorna error para cp inválido' do
    get '/api/postal_codes', params: { cp: 'abc' }
    expect(response.status).to eq(422)
    expect(JSON.parse(response.body)['error']).to eq('invalid_cp')
  end

  it 'retorna not found cuando no existe' do
    get '/api/postal_codes', params: { cp: '99999' }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['found']).to be false
  end

  it 'retorna colonias y municipio/estado cuando existe' do
    get '/api/postal_codes', params: { cp: '36500' }
    body = JSON.parse(response.body)
    expect(body['found']).to be true
    expect(body['municipio']).to eq('irapuato')
    expect(body['colonias'].sort).to eq(['centro','modulo i'])
  end
end
