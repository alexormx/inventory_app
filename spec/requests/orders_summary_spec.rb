require 'rails_helper'

RSpec.describe "Orders summary", type: :request do
  before(:all) { Rails.application.reload_routes! }
  let(:user) { create(:user, password: 'password123', password_confirmation: 'password123') }

  it 'renders summary page with raw path' do
    sign_in user
    order = create(:sale_order, user: user)
    get summary_order_path(order), headers: { 'ACCEPT' => 'text/html' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id.to_s)
  end
end
