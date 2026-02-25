require 'rails_helper'
require 'cgi'

RSpec.describe 'Admin::SaleOrders show piece locations', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  before { sign_in admin }

  it 'shows location toggle and location path when order is Confirmed' do
    sale_order = create(:sale_order, user: customer, status: 'Confirmed')
    sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1)

    warehouse = create(:inventory_location, :warehouse, name: 'Bodega A')
    location = create(:inventory_location, :shelf, name: 'Anaquel 1', parent: warehouse)

    create(:inventory,
           product: product,
           sale_order: sale_order,
           sale_order_item: sale_order_item,
           status: :reserved,
           inventory_location: location)

    get admin_sale_order_path(sale_order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Ver ubicaciones')
    expect(response.body).to include(CGI.escapeHTML(location.full_path))
  end

  it 'hides location toggle when order is In Transit' do
    sale_order = create(:sale_order, user: customer, status: 'In Transit')
    sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1)

    warehouse = create(:inventory_location, :warehouse, name: 'Bodega B')
    location = create(:inventory_location, :shelf, name: 'Anaquel 2', parent: warehouse)

    create(:inventory,
           product: product,
           sale_order: sale_order,
           sale_order_item: sale_order_item,
           status: :reserved,
           inventory_location: location)

    get admin_sale_order_path(sale_order)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Ver ubicaciones')
  end
end
