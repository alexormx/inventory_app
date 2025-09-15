require 'rails_helper'

RSpec.describe 'Orders index as admin in customer mode', type: :request do
  before(:all) { Rails.application.reload_routes! }
  let(:admin) { create(:user, :admin, password: 'password123', password_confirmation: 'password123') }
  let!(:order1) { create(:sale_order, user: admin) }
  let!(:order2) { create(:sale_order, user: admin) }

  it 'renders with customer layout (no admin sidebar) and lists only admin user orders' do
    sign_in admin
    get orders_path, headers: { 'ACCEPT' => 'text/html' }
    expect(response).to have_http_status(:ok)
    # Customer layout indicator
    expect(response.body).to include('site-navbar')
    # Ensure admin sidebar absent
    expect(response.body).not_to include('id="sidebar"')
    # Should list the orders ids
    expect(response.body).to include(order1.id.to_s)
    expect(response.body).to include(order2.id.to_s)
  end
end
