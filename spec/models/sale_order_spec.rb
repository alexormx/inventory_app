require 'rails_helper'

RSpec.describe SaleOrder, type: :model do
  let(:customer) { create(:user, role: "customer") }
  let(:product)  { create(:product) }

  it "destroys and releases reserved items" do
    so = create(:sale_order, user: customer, status: "Pending")
    create(:sale_order_item, sale_order: so, product: product, quantity: 2)
    # crea inventories reserved vía callback

    expect { so.destroy }.to change { SaleOrder.count }.by(-1)
    expect(Inventory.where(sale_order_id: so.id)).to be_empty
  end

  it "blocks destroy when sold exists" do
    customer = create(:user, role: "customer")
    product  = create(:product)

    so  = create(:sale_order, user: customer, status: "Pending", subtotal: 100, tax_rate: 0, total_tax: 0, total_order_value: 100)
    soi = create(:sale_order_item, sale_order: so, product: product, quantity: 1, unit_final_price: 100, total_line_cost: 100)

    inv = Inventory.find_by(sale_order_id: so.id, product_id: product.id) ||
          Inventory.create!(product: product, sale_order_id: so.id, purchase_cost: 100, status: :reserved)

    inv.update!(status: :sold)

    expect(so.destroy).to be_falsey
    expect(SaleOrder.exists?(so.id)).to be(true)
    expect { so.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed, /Failed to destroy SaleOrderItem/)
  end
end