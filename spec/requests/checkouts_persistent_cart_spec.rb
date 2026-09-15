# frozen_string_literal: true

require 'rails_helper'

# Checkout consumes the durable-backed cart and closes it as `converted` in
# the same transaction that creates the SaleOrder.
RSpec.describe 'Checkout and the persistent cart', type: :request do
  let(:password) { 'password123' }
  let!(:user) { create(:user, password: password) }
  let!(:product) { create(:product, selling_price: 10.0, minimum_price: 5.0) }
  let!(:other_product) { create(:product, selling_price: 20.0, minimum_price: 5.0) }
  let!(:address) { create(:shipping_address, user: user, default: true) }
  let!(:payment_method) { create(:payment_method, code: 'efectivo', name: 'Efectivo', active: true) }
  let!(:shipping_method) { create(:shipping_method, :standard) }

  before { sign_in user }

  def prepare_checkout
    post checkout_step2_path, params: { selected_address_id: address.id, shipping_method: 'standard' }
    get checkout_step3_path
    session[:checkout_token]
  end

  def complete(token)
    post checkout_complete_path, params: { payment_method: 'efectivo', checkout_token: token }
  end

  it 'converts the active cart atomically with the order and clears the projection' do
    post cart_items_path, params: { product_id: product.id }
    post cart_items_path, params: { product_id: product.id }
    cart = user.shopping_carts.sole
    token = prepare_checkout

    expect { complete(token) }.to change(SaleOrder, :count).by(1)
    order = user.sale_orders.sole
    expect(response).to redirect_to(checkout_thank_you_path(order_id: order.id))

    cart.reload
    expect(cart.status).to eq('converted')
    expect(cart.sale_order_id).to eq(order.id)
    expect(cart.converted_at).to be_present
    expect(cart.closed_at).to be_present
    expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 2]])
    expect(order.sale_order_items.pluck(:product_id, :quantity)).to eq([[product.id, 2]])

    expect(session[:cart]).to eq({})
    get cart_path
    expect(session[:cart]).to eq({})
    expect(session[:cart_reconciled]).to include('cart_id' => nil)
    expect(user.shopping_carts.where(status: 'active')).to be_empty
  end

  it 'starts a fresh active cart after conversion and never touches the converted one' do
    post cart_items_path, params: { product_id: product.id }
    converted = user.shopping_carts.sole
    complete(prepare_checkout)
    expect(converted.reload.status).to eq('converted')

    post cart_items_path, params: { product_id: other_product.id }
    fresh = user.shopping_carts.find_by(status: 'active')
    expect(fresh).to be_present
    expect(fresh).not_to eq(converted)
    expect(fresh.shopping_cart_items.pluck(:product_reference)).to eq([other_product.id])
    expect(converted.reload.shopping_cart_items.pluck(:product_reference)).to eq([product.id])
    expect(user.shopping_carts.count).to eq(2)
  end

  it 'leaves the cart ACTIVE with its contents when checkout fails' do
    post cart_items_path, params: { product_id: product.id }
    cart = user.shopping_carts.sole
    token = prepare_checkout
    allow(InventoryServices::ReserveSaleOrderItem).to receive(:call)
      .and_raise(InventoryServices::ReserveSaleOrderItem::InsufficientInventory, 'sin stock')

    expect { complete(token) }.not_to change(SaleOrder, :count)
    expect(response).to redirect_to(checkout_step3_path)

    cart.reload
    expect(cart.status).to eq('active')
    expect(cart.converted_at).to be_nil
    expect(cart.closed_at).to be_nil
    expect(cart.sale_order_id).to be_nil
    expect(cart.shopping_cart_items.pluck(:product_reference, :quantity)).to eq([[product.id, 1]])
    get cart_path
    expect(session[:cart]).to eq(product.id.to_s => { 'brand_new' => 1 })
  end

  # The cross-connection race itself (another tab's add committing before the
  # conversion locks the cart) is exercised in
  # spec/services/shopping_carts/active_cart_mutation_concurrency_spec.rb and
  # spec/services/shopping_carts/convert_cart_spec.rb. This example covers the
  # request path: CartChanged rolls the whole order back and tells the
  # customer. Inside transactional fixtures the injected write shares the
  # checkout connection, so it rolls back with the order here.
  it 'refuses to convert a cart that changed after the checkout snapshot, and rolls the order back' do
    post cart_items_path, params: { product_id: product.id }
    cart = user.shopping_carts.sole
    token = prepare_checkout
    allow(ShoppingCarts::ConvertCart).to receive(:call).and_wrap_original do |m, **kwargs|
      ShoppingCarts::ActiveCartMutation.add(user: user, product: other_product, condition: 'brand_new')
      m.call(**kwargs)
    end

    expect { complete(token) }.not_to change(SaleOrder, :count)
    expect(response).to redirect_to(checkout_step3_path)
    expect(flash[:alert]).to include('carrito cambió')

    cart.reload
    expect(cart.status).to eq('active')
    expect(cart.converted_at).to be_nil
    expect(cart.shopping_cart_items.pluck(:product_reference)).to eq([product.id])
    expect(SaleOrderItem.count).to eq(0)
    expect(Inventory.where.not(sale_order_id: nil).count).to eq(0)
  end

  it 'a repeated submit after success is recognised as already processed and converts nothing twice' do
    post cart_items_path, params: { product_id: product.id }
    token = prepare_checkout
    complete(token)
    order = user.sale_orders.sole

    complete(token)

    expect(response).to redirect_to(checkout_thank_you_path(order_id: order.id))
    expect(SaleOrder.count).to eq(1)
    expect(user.shopping_carts.where(status: 'converted').count).to eq(1)
  end

  it 'does not resurrect the converted cart on logout and a fresh login' do
    post cart_items_path, params: { product_id: product.id }
    complete(prepare_checkout)

    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: password } }

    expect(session[:cart]).to be_blank
    get cart_path
    expect(response.body).not_to include(product.product_name)
    expect(user.shopping_carts.where(status: 'active')).to be_empty
    expect(CartSessionImport.count).to eq(0)
  end

  it 'prices from the current product at checkout time, never from the persistent row' do
    post cart_items_path, params: { product_id: product.id }
    product.update!(selling_price: 15.0)
    complete(prepare_checkout)

    expect(user.sale_orders.sole.sale_order_items.sole.unit_selling_price.to_d).to eq(15.to_d)
    expect(ShoppingCartItem.column_names).not_to include('price', 'unit_price')
  end
end
