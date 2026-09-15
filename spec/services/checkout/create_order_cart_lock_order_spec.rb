# frozen_string_literal: true

require 'rails_helper'

# Lock-order audit for the persistent cart stack, on real PostgreSQL
# connections. Inserting a shopping_cart_items row takes an implicit
# FOR KEY SHARE on the referenced product (foreign key), which conflicts with
# the FOR UPDATE checkout takes on products. Every cart writer locks the cart
# row first, so checkout must lock the cart BEFORE the products or the two
# form a cycle: mutation holds cart -> waits on product; checkout holds
# product -> waits on cart.
RSpec.describe Checkout::CreateOrder, 'lock order against cart mutations', type: :model do
  self.use_transactional_tests = false

  TABLES_LOCK_ORDER = %w[
    cart_session_imports shopping_cart_items shopping_carts
    payments order_shipping_addresses preorder_reservations sale_order_items sale_orders
    inventories inventory_locations products shipping_addresses users shipping_methods payment_methods
  ].freeze

  def assert_isolated_test_database!
    db = ActiveRecord::Base.connection.current_database
    raise "refusing to truncate outside the test environment (#{Rails.env})" unless Rails.env.test?
    raise "refusing to truncate #{db}" if db.include?('development') || db.include?('production')
  end

  def clean!
    assert_isolated_test_database!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{TABLES_LOCK_ORDER.join(', ')} RESTART IDENTITY CASCADE")
  end

  before { clean! }
  after { clean! }

  def with_connection
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { yield }
    rescue StandardError => e
      e
    end
  end

  it 'a new-line add during checkout waits for the conversion and lands in a fresh cart, with no deadlock' do
    user = create(:user)
    product = create(:product, selling_price: 10.0, minimum_price: 5.0)
    address = create(:shipping_address, user: user, default: true)
    create(:payment_method, code: 'efectivo', name: 'Efectivo', active: true)
    create(:shipping_method, :standard)
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new')
    cart = ShoppingCart.sole
    snapshot = Cart.new({ cart: ShoppingCarts::SessionHydrator.call(cart) })

    products_locked = Queue.new
    allow(InventoryServices::ReserveSaleOrderItem).to receive(:call).and_wrap_original do |m, *args, **kwargs, &blk|
      # Runs after checkout locked the products; give the other tab time to
      # start its INSERT (FOR KEY SHARE on the same product).
      products_locked << true
      sleep 1.5
      m.call(*args, **kwargs, &blk)
    end

    checkout = with_connection do
      described_class.new(
        user: user, cart: snapshot, shipping_address_id: address.id, shipping_method: 'standard',
        payment_method: 'efectivo', notes: '', idempotency_key: 'lock-order', shopping_cart: cart
      ).call
    end
    mutation = with_connection do
      raise 'checkout never locked the products' if products_locked.pop(timeout: 10).nil?

      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'misb')
    end

    checkout_result = checkout.value
    mutation_result = mutation.value

    expect(checkout_result).not_to be_a(Exception), checkout_result.inspect
    expect(mutation_result).not_to be_a(Exception), mutation_result.inspect
    expect(checkout_result).to be_success
    expect(cart.reload.status).to eq('converted')
    expect(cart.shopping_cart_items.pluck(:product_reference, :condition)).to eq([[product.id, 'brand_new']])

    expect(mutation_result.status).to eq(:ok)
    fresh = ShoppingCart.find_by(user_id: user.id, status: 'active')
    expect(fresh).to be_present
    expect(fresh.shopping_cart_items.pluck(:product_reference, :condition)).to eq([[product.id, 'misb']])
  end
end
