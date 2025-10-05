require 'rails_helper'

RSpec.describe 'Liberación de inventario al eliminar SaleOrderItem', type: :model do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:sale_order) { create(:sale_order) }

  it 'al destruir la línea libera inventario reservado limpiando sale_order_id, sale_order_item_id y sold_price' do
    # Creamos inventario disponible
    inv1 = Inventory.create!(product: product, purchase_cost: 12.5, status: :available)
    inv2 = Inventory.create!(product: product, purchase_cost: 12.5, status: :available)

    # Creamos la línea (quantity 2) que reservará 2 unidades
    soi = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2, unit_cost: 10)

    # Forzamos sync (after_save quantity change ya lo hace, pero aseguramos estado)
    soi.reload

    reserved = Inventory.where(product_id: product.id, sale_order_id: sale_order.id, status: Inventory.statuses[:reserved])
    expect(reserved.count).to eq(2)

    # Asignamos sold_price a las piezas reservadas
    reserved.update_all(sold_price: 99.99)

    # Destroy la línea
    soi.destroy!

    # Las piezas deben estar ahora available sin referencias ni sold_price
    reserved.each do |prev|
      prev.reload
      expect(prev.status).to eq('available')
      expect(prev.sale_order_id).to be_nil
      expect(prev.sale_order_item_id).to be_nil
      expect(prev.sold_price).to be_nil
    end
  end
end
