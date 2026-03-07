# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SEO routing hardening', type: :request do
  before do
    host! 'localhost'
  end

  it 'redirects legacy privacy route to canonical URL' do
    get '/pages/privacy_notice'

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to('/aviso-de-privacidad')
  end

  it 'redirects legacy cart route to canonical URL' do
    get '/carts/show'

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to('/cart')
  end

  it 'redirects legacy products index route to catalog' do
    get '/products/index'

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to('/catalog')
  end

  it 'protects api docs behind authentication' do
    get '/api-docs'

    expect(response).to have_http_status(:found)
    expect(response.location).to end_with('/users/sign_in')
  end
end