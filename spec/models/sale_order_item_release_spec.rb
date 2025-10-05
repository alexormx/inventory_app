require 'rails_helper'

RSpec.describe SaleOrderItem, type: :model do
  describe 'inventory release on destroy' do
    let(:product) { create(:product, skip_seed_inventory: true) }
    let!(:available_units) { 3.times.map { create(:inventory, product: product, status: :available, purchase_cost: 5) } }
    let(:sale_order) { create(:sale_order) }

    it 'releases reserved inventory back to available when line is destroyed' do
      item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 2, unit_cost: 10, unit_final_price: 10, total_line_cost: 20)
      # Forzar sync (after_save con change de quantity ya lo hace, pero aseguramos estado)
      expect(Inventory.where(product: product, sale_order_id: sale_order.id, status: :reserved).count).to eq 2

      # Destroy
      item.destroy

      # Deben liberarse: reserved -> available y sin referencias a la SO
      freed = Inventory.where(product: product, sale_order_id: nil, status: :available)
      expect(freed.count).to be >= 2
    end

    it 'does not allow destroy if there are sold items' do
      item = create(:sale_order_item, sale_order: sale_order, product: product, quantity: 1, unit_cost: 10, unit_final_price: 10, total_line_cost: 10)
      # Marcar esa unidad como vendida
      inv = Inventory.find_by(product: product, sale_order_id: sale_order.id)
      inv.update!(status: :sold)
      expect(inv.reload.status).to eq 'sold'

      expect(item.destroy).to be_falsey
      expect(item.errors.full_messages.join).to match(/No se puede eliminar la línea/)
    end
  end
end
