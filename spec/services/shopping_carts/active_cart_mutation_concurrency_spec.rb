# frozen_string_literal: true

require 'rails_helper'

# Real PostgreSQL races on the mutation path: separate connections and
# transactions, arbitrated by the cart row lock, the one-active-cart partial
# unique index and the item unique index. Transactional fixtures are off.
RSpec.describe ShoppingCarts::ActiveCartMutation, 'under concurrency', type: :model do
  self.use_transactional_tests = false

  CART_TABLES_C = %w[cart_session_imports shopping_cart_items shopping_carts].freeze
  MAX_PARALLEL_C = 4
  TIMEOUT_C = 15

  def assert_isolated_test_database!
    db = ActiveRecord::Base.connection.current_database
    raise "refusing to truncate outside the test environment (#{Rails.env})" unless Rails.env.test?
    raise "refusing to truncate #{db}" if db.include?('development') || db.include?('production')
  end

  def clean!
    assert_isolated_test_database!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{CART_TABLES_C.join(', ')} RESTART IDENTITY CASCADE")
    SaleOrder.where(id: @order_ids.to_a).find_each(&:destroy!) if @order_ids
    Product.where(id: @product_ids.to_a).find_each(&:destroy!) if @product_ids
    User.where(id: @user_ids.to_a).find_each(&:destroy!) if @user_ids
  end

  before do
    clean!
    @user_ids = Set.new
    @product_ids = Set.new
    @order_ids = Set.new
  end

  after { clean! }

  def new_user
    create(:user).tap { |u| @user_ids << u.id }
  end

  def new_product
    create(:product, skip_seed_inventory: true).tap { |p| @product_ids << p.id }
  end

  def run_in_parallel(count)
    raise ArgumentError, "at most #{MAX_PARALLEL_C}" if count > MAX_PARALLEL_C

    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          raise 'barrier start timed out' if start.pop(timeout: TIMEOUT_C).nil?

          outcomes << [:ok, yield(index)]
        rescue StandardError => e
          outcomes << [:error, e]
        end
      end
    end
    count.times { raise 'barrier ready timed out' if ready.pop(timeout: TIMEOUT_C).nil? }
    count.times { start << true }
    threads.each { |t| t.join(TIMEOUT_C * 2) or raise 'thread did not finish' }
    count.times.map { outcomes.pop(timeout: 1) or raise 'missing outcome' }
  end

  def lines
    ShoppingCartItem.pluck(:product_reference, :condition, :quantity).map { |r, c, q| [r, c, q] }.sort
  end

  def expect_all_ok(outcomes)
    errors = outcomes.select { |k, _| k == :error }.map(&:last)
    expect(errors).to be_empty, errors.map(&:full_message).join("\n")
  end

  it 'same line added from 4 requests at once: one cart, one row, quantity 3 + one refusal at the cap' do
    user = new_user
    product = new_product

    outcomes = run_in_parallel(4) { described_class.add(user: user, product: product, condition: 'brand_new') }

    expect_all_ok(outcomes)
    statuses = outcomes.map { |_, r| r.status }
    expect(statuses.count(:ok)).to eq(Cart::MAX_NEW_ITEMS_PER_PRODUCT)
    expect(statuses.count(:limit_exceeded)).to eq(1)
    expect(ShoppingCart.count).to eq(1)
    expect(lines).to eq([[product.id, 'brand_new', Cart::MAX_NEW_ITEMS_PER_PRODUCT]])
  end

  it 'two quantity updates race: the durable result is exactly one of the two intended values' do
    user = new_user
    product = new_product
    described_class.add(user: user, product: product, condition: 'brand_new')

    outcomes = run_in_parallel(2) do |i|
      described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: i + 2)
    end

    expect_all_ok(outcomes)
    expect(outcomes.map { |_, r| r.status }).to all(eq(:ok))
    expect([[[product.id, 'brand_new', 2]], [[product.id, 'brand_new', 3]]]).to include(lines)
  end

  it 'remove vs add on the same line converge to a valid state without duplicates' do
    user = new_user
    product = new_product
    described_class.add(user: user, product: product, condition: 'brand_new')

    outcomes = run_in_parallel(2) do |i|
      if i.zero?
        described_class.remove(user: user, product: product, condition: 'brand_new')
      else
        described_class.add(user: user, product: product, condition: 'brand_new')
      end
    end

    expect_all_ok(outcomes)
    expect([[], [[product.id, 'brand_new', 1]], [[product.id, 'brand_new', 2]]]).to include(lines)
    expect(ShoppingCartItem.where(product_reference: product.id).count).to be <= 1
  end

  it 'clear vs add leaves either an empty cart or exactly the added line' do
    user = new_user
    a = new_product
    b = new_product
    described_class.add(user: user, product: a, condition: 'brand_new')

    outcomes = run_in_parallel(2) do |i|
      i.zero? ? described_class.clear(user: user) : described_class.add(user: user, product: b, condition: 'brand_new')
    end

    expect_all_ok(outcomes)
    expect([[], [[b.id, 'brand_new', 1]]]).to include(lines)
    expect(ShoppingCart.count).to eq(1)
  end

  it 'first mutations racing for a user create exactly one active cart' do
    user = new_user
    products = Array.new(4) { new_product }

    outcomes = run_in_parallel(4) { |i| described_class.add(user: user, product: products[i], condition: 'brand_new') }

    expect_all_ok(outcomes)
    expect(outcomes.map { |_, r| r.status }).to all(eq(:ok))
    expect(ShoppingCart.count).to eq(1)
    expect(lines.size).to eq(4)
  end

  it 'a mutation racing a checkout conversion never lands in the converted cart' do
    user = new_user
    product = new_product
    other = new_product
    described_class.add(user: user, product: product, condition: 'brand_new')
    cart = ShoppingCart.sole
    order = create(:sale_order, user: user).tap { |o| @order_ids << o.id }
    inside = Queue.new

    outcomes = run_in_parallel(2) do |i|
      if i.zero?
        ActiveRecord::Base.transaction do
          ShoppingCarts::ConvertCart.call(cart: cart, sale_order: order, lines: [[product.id, 'brand_new', 1]])
          inside << true
          sleep 0.5 # hold the converted-but-uncommitted cart while the add arrives
        end
        :converted
      else
        raise 'conversion never started' if inside.pop(timeout: 10).nil?

        described_class.add(user: user, product: other, condition: 'brand_new').status
      end
    end

    expect_all_ok(outcomes)
    expect(outcomes.map(&:last)).to contain_exactly(:converted, :ok)
    expect(cart.reload.status).to eq('converted')
    expect(cart.shopping_cart_items.pluck(:product_reference)).to eq([product.id])
    fresh = ShoppingCart.find_by(status: 'active', user_id: user.id)
    expect(fresh).to be_present
    expect(fresh.shopping_cart_items.pluck(:product_reference)).to eq([other.id])
  end
end
