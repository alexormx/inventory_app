require 'rails_helper'

# Behavior after enforcing customer-only layout in OrdersController:
# - Admins should NOT be able to fetch another user's order via customer route (/orders/:id/summary)
#   (raises ActiveRecord::RecordNotFound -> 404)
# - Admins MUST use the admin namespace route (/admin/sale_orders/:id/summary) to view any order.
RSpec.describe 'Admin access sale order summary (admin namespace)', type: :request do
  # En algunos runs (con enable_reloading=true) los helpers pueden no estar cargados aún
  before(:all) { Rails.application.reload_routes! }
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let!(:order) { create(:sale_order, user: customer) }

  it 'allows admin to view customer order summary via admin namespace route' do
    sign_in admin
    get summary_admin_sale_order_path(order)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id) # custom SO-* id present in summary
  end

  it 'returns 404 when admin tries customer summary route for another user order' do
    sign_in admin
    get summary_order_path(order)
    expect(response).to have_http_status(:not_found)
  end
end
