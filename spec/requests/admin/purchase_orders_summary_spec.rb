require 'rails_helper'

RSpec.describe 'Admin PurchaseOrders summary', type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:supplier) { create(:user) }
  let!(:purchase_order) { create(:purchase_order, user: supplier) }

  before { sign_in admin }

  it 'renders compact summary page' do
    get summary_admin_purchase_order_path(purchase_order)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(purchase_order.id)
  end
end
