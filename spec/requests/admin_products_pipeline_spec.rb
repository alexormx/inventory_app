require 'rails_helper'

RSpec.describe 'Admin::Products pipeline', type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }

  before do
    login_as(admin, scope: :user)
  end

  describe 'tabs and counts' do
    it 'renders drafts tab within turbo-frame and shows dynamic counts' do
      create_list(:product, 2, status: 'draft')
      create(:product, status: 'active')
      create_list(:product, 3, status: 'inactive')

      get admin_products_drafts_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('turbo-frame id="products_frame"')
      expect(body).to include('Drafts (2)')
      expect(body).to include('Active (1)')
      expect(body).to include('Inactive (3)')
    end
  end

  describe 'activation/deactivation via turbo stream' do
    it 'activates from draft tab and returns turbo stream replacing products_frame' do
      product = create(:product, status: 'draft')
      headers = { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

  patch activate_admin_product_path(product), params: { source_tab: 'draft' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(product.reload.status).to eq('active')
      # Must contain a turbo-stream replacement of the products frame and include the frame wrapper inside
      expect(response.body).to include('turbo-stream action="replace"')
      expect(response.body).to include('target="products_frame"')
      expect(response.body).to include('<turbo-frame id="products_frame"')
    end

    it 'deactivates from active tab and returns turbo stream replacing products_frame' do
      product = create(:product, status: 'active')
      headers = { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

  patch deactivate_admin_product_path(product), params: { source_tab: 'active' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(product.reload.status).to eq('inactive')
      expect(response.body).to include('turbo-stream action="replace"')
      expect(response.body).to include('target="products_frame"')
      expect(response.body).to include('<turbo-frame id="products_frame"')
    end
  end

  describe 'pagination' do
    it 'shows at most 12 products per page on drafts tab' do
      create_list(:product, 15, status: 'draft')

      get admin_products_drafts_path
      expect(response).to have_http_status(:ok)
      # Count product cards rendered on the page
      cards = response.body.scan(/class=\"[^\"]*product-card[^\"]*\"/)
      expect(cards.length).to be <= 12

      get admin_products_drafts_path(page: 2)
  cards_page2 = response.body.scan(/class=\"[^\"]*product-card[^\"]*\"/)
  expect(cards_page2.length).to be <= 12
  # Segunda página debe tener al menos 1 elemento
  expect(cards_page2.length).to be >= 1
    end
  end
end
