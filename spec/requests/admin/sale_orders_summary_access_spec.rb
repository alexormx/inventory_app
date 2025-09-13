require 'rails_helper'

RSpec.describe 'Admin access customer order summary', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let!(:order) { create(:sale_order, user: customer) }

  it 'allows admin to view customer summary' do
    sign_in admin
    get summary_order_path(order)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id)
  end
end
