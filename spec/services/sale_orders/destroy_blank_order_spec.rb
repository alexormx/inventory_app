# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::DestroyBlankOrder do
  let(:order) { create(:sale_order, total_order_value: 0, subtotal: 0) }

  it 'deletes a blank pending order with its shipping snapshot and unpaid payments' do
    create(:order_shipping_address, sale_order: order)
    create(:payment, sale_order: order, amount: 50, status: 'Pending')

    result = described_class.call(order)

    expect(result).to be_success
    expect(SaleOrder.exists?(order.id)).to be(false)
    expect(Payment.where(sale_order_id: order.id)).to be_empty
    expect(OrderShippingAddress.where(sale_order_id: order.id)).to be_empty
  end

  it 'deletes a blank canceled order' do
    order.update_columns(status: 'Canceled')

    expect(described_class.call(order)).to be_success
  end

  it 'deletes a blank $0 order that confirmed itself' do
    order.update_columns(status: 'Confirmed')

    expect(described_class.call(order)).to be_success
  end

  # Un pedido hecho en la tienda al que se le quitaron los productos: trae su
  # carrito convertido (y el anónimo que se fusionó al iniciar sesión), un
  # envío sin despachar, líneas canceladas e historial de piezas.
  it 'deletes an emptied store order, cleaning its traces but keeping inventory history' do
    product = create(:product, skip_seed_inventory: true)
    owned_cart = create(:shopping_cart, :owned, user: order.user, status: 'converted', sale_order: order,
                                                converted_at: Time.current, closed_at: Time.current)
    anonymous_cart = create(:shopping_cart, status: 'merged', merged_into_cart: owned_cart, closed_at: Time.current)
    create(:shopping_cart_item, shopping_cart: owned_cart)
    create(:cart_session_import, shopping_cart: owned_cart)
    create(:shipment, sale_order: order, status: :pending)
    CanceledOrderItem.insert_all!([{ sale_order_id: order.id, product_id: product.id, canceled_quantity: 1,
                                     sale_price_at_cancellation: 100, cancellation_reason: 'prueba' }])
    request = create(:whatsapp_request, sale_order_id: order.id, status: :converted)
    unit = create(:inventory, product: product)
    event = InventoryEvent.create!(inventory: unit, product: product, event_type: 'sale_order_link_cleared',
                                   previous_sale_order_id: order.id)

    result = described_class.call(order)

    expect(result).to be_success
    expect(SaleOrder.exists?(order.id)).to be(false)
    expect(ShoppingCart.where(id: [owned_cart.id, anonymous_cart.id])).to be_empty
    expect(Shipment.where(sale_order_id: order.id)).to be_empty
    expect(CanceledOrderItem.where(sale_order_id: order.id)).to be_empty
    expect(request.reload.sale_order_id).to be_nil
    expect(event.reload.previous_sale_order_id).to eq(order.id)
  end

  it 'keeps orders that have products' do
    create(:sale_order_item, sale_order: order)

    result = described_class.call(order)

    expect(result).not_to be_success
    expect(result.reasons).to include('tiene productos')
    expect(SaleOrder.exists?(order.id)).to be(true)
  end

  it 'keeps orders with received payments, a dispatched shipment or assigned inventory' do
    create(:payment, sale_order: order, amount: 10, status: 'Completed')
    create(:shipment, sale_order: order, status: :shipped)
    create(:inventory, sale_order: order, status: :reserved)

    reasons = described_class.blocking_reasons(order.reload)

    expect(reasons).to include('tiene pagos recibidos o reembolsados', 'el envío ya se despachó',
                               'tiene piezas de inventario asignadas')
  end

  it 'keeps orders already in preparation or shipped, even when blank' do
    order.update_columns(status: 'Preparing')

    expect(described_class.blocking_reasons(order)).to include('solo se pueden borrar pedidos pendientes, confirmados o cancelados')
  end
end
