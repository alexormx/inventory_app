# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrderItem, '#preorder callbacks', type: :model do
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:order) { create(:sale_order) }

  let(:records) do
    first_line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
      quantity: 2,
      preorder_quantity: 2
    )
    second_line = create(
      :sale_order_item,
      sale_order: order,
      product: product,
      quantity: 2,
      preorder_quantity: 2
    )
    first_reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: first_line,
      quantity: 2,
      reserved_at: 2.days.ago
    )
    second_reservation = create(
      :preorder_reservation,
      product: product,
      user: order.user,
      sale_order: order,
      sale_order_item: second_line,
      quantity: 2,
      reserved_at: 1.day.ago
    )

    {
      first_line: first_line,
      second_line: second_line,
      first_reservation: first_reservation,
      second_reservation: second_reservation
    }
  end

  it 'reduces only the reservation linked to the changed line' do
    records[:second_line].update!(quantity: 1)

    expect(records[:first_reservation].reload.quantity).to eq(2)
    expect(records[:second_reservation].reload.quantity).to eq(1)
  end

  it 'cancels only the reservation linked to the destroyed line' do
    records[:first_line].destroy!

    expect(records[:first_reservation].reload).to be_cancelled
    expect(records[:first_reservation].sale_order_item).to be_nil
    expect(records[:second_reservation].reload).to be_pending
    expect(records[:second_reservation].sale_order_item).to eq(records[:second_line])
  end
end
