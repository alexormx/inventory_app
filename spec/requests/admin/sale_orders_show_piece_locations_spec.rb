require 'rails_helper'
require 'cgi'

RSpec.describe 'Admin::SaleOrders show piece locations', type: :request do
  before(:all) { Rails.application.reload_routes! }

  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  before { sign_in admin }

  it 'groups piece locations inline when multiple units share the same location' do
    sale_order = create(:sale_order, user: customer, status: 'Confirmed')
    sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2)

    warehouse = create(:inventory_location, :warehouse, name: 'Bodega A')
    location = create(:inventory_location, :shelf, name: 'Anaquel 1', parent: warehouse)

    inventories = Array.new(2) do
      create(:inventory,
             product: product,
             sale_order: sale_order,
             sale_order_item: sale_order_item,
             status: :reserved,
             inventory_location: location)
    end

    get admin_sale_order_path(sale_order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Ubicaciones')
    expect(response.body).to include(CGI.escapeHTML(location.full_path))
    expect(response.body).to include('2 piezas')
    inventories.each do |inventory|
      expect(response.body).to include("##{inventory.id}")
    end
  end

  it 'separates grouped piece locations when units are in different locations' do
    sale_order = create(:sale_order, user: customer, status: 'Confirmed')
    sale_order_item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2)

    warehouse = create(:inventory_location, :warehouse, name: 'Bodega C')
    location_a = create(:inventory_location, :shelf, name: 'Anaquel 3', parent: warehouse)
    location_b = create(:inventory_location, :shelf, name: 'Anaquel 4', parent: warehouse)

    inventory_a = create(:inventory,
                         product: product,
                         sale_order: sale_order,
                         sale_order_item: sale_order_item,
                         status: :reserved,
                         inventory_location: location_a)
    inventory_b = create(:inventory,
                         product: product,
                         sale_order: sale_order,
                         sale_order_item: sale_order_item,
                         status: :reserved,
                         inventory_location: location_b)

    get admin_sale_order_path(sale_order)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(location_a.full_path))
    expect(response.body).to include(CGI.escapeHTML(location_b.full_path))
    expect(response.body).to include("##{inventory_a.id}")
    expect(response.body).to include("##{inventory_b.id}")
  end

  it 'hides piece locations section when order is In Transit' do
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
    expect(response.body).not_to include(CGI.escapeHTML(location.full_path))
    expect(response.body).not_to include("##{Inventory.last.id}")
  end
end
