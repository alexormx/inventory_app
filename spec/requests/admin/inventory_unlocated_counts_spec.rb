# frozen_string_literal: true

require 'rails_helper'

# "Sin ubicación" tiene una sola definición: Inventory::STATUSES_REQUIRING_LOCATION.
# El índice de inventario la tenía escrita a mano como [available, reserved] y
# omitía pre_reserved, así que sus contadores discrepaban del explorador de
# ubicaciones y del desglose por producto en cuanto había una pieza pre-reservada.
RSpec.describe 'Admin::Inventory unlocated counters', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Contador', product_sku: 'SKU-CNT') }
  let(:location) { create(:inventory_location, :warehouse) }

  before { sign_in admin }

  it 'counts every status that requires a location, pre_reserved included' do
    create(:inventory, product: product, status: :available, inventory_location_id: nil, purchase_cost: 10)
    create(:inventory, product: product, status: :reserved, inventory_location_id: nil, purchase_cost: 10)
    create(:inventory, product: product, status: :pre_reserved, inventory_location_id: nil, purchase_cost: 10)
    create(:inventory, product: product, status: :available, inventory_location: location, purchase_cost: 10)
    create(:inventory, product: product, status: :pre_reserved, inventory_location: location, purchase_cost: 10)

    get admin_inventory_index_path

    expect(response).to have_http_status(:success)
    expect(controller.instance_variable_get(:@unlocated_count)).to eq(3)
    expect(controller.instance_variable_get(:@located_count)).to eq(2)
  end

  it 'ignores statuses that do not require a location' do
    create(:inventory, product: product, status: :available, inventory_location_id: nil, purchase_cost: 10)
    Inventory::STATUSES_WITHOUT_LOCATION.each do |status|
      create(:inventory, product: product, status: status, inventory_location_id: nil, purchase_cost: 10)
    end

    get admin_inventory_index_path

    expect(response).to have_http_status(:success)
    expect(controller.instance_variable_get(:@unlocated_count)).to eq(1)
  end

  # Los contadores del índice y el total del explorador miran el mismo universo;
  # si vuelven a divergir, esto lo detecta.
  it 'agrees with the location explorer total for the same data' do
    create(:inventory, product: product, status: :available, inventory_location_id: nil, purchase_cost: 10)
    create(:inventory, product: product, status: :pre_reserved, inventory_location_id: nil, purchase_cost: 10)
    create(:inventory, product: product, status: :sold, inventory_location_id: nil, purchase_cost: 10)

    get admin_inventory_index_path
    index_unlocated = controller.instance_variable_get(:@unlocated_count)

    get admin_inventory_location_explorer_path(mode: 'unlocated')
    explorer_total = controller.instance_variable_get(:@total_pieces)

    expect(index_unlocated).to eq(explorer_total)
    expect(index_unlocated).to eq(2)
  end

  it 'does not change inventory while rendering' do
    piece = create(:inventory, product: product, status: :available,
                               inventory_location_id: nil, purchase_cost: 10)

    expect do
      get admin_inventory_index_path
      get admin_inventory_location_explorer_path(mode: 'unlocated')
    end.not_to(change { piece.reload.attributes })
  end
end
