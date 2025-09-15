require 'rails_helper'

RSpec.describe 'Order summary layout context', type: :request do
  before(:all) { Rails.application.reload_routes! }
  let(:admin) { create(:user, :admin, password: 'password123', password_confirmation: 'password123') }
  let(:customer) { create(:user, password: 'password123', password_confirmation: 'password123') }
  let!(:order) { create(:sale_order, user: customer) }

  context 'when accessed from admin with admin_context=1' do
    it 'renders using admin layout (sidebar present)' do
      sign_in admin
      get summary_order_path(order, admin_context: 1), headers: { 'ACCEPT' => 'text/html' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="sidebar"')
      expect(response.body).not_to include('site-navbar')
    end
  end

  context 'when accessed by customer (no param)' do
    it 'renders using customer layout (customer navbar present)' do
      sign_in customer
      get summary_order_path(order), headers: { 'ACCEPT' => 'text/html' }
      expect(response.body).to include('site-navbar')
      expect(response.body).not_to include('id="sidebar"')
    end
  end
end
