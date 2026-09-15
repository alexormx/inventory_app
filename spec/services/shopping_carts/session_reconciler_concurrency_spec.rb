# frozen_string_literal: true

require 'rails_helper'

# Real PostgreSQL races, not mocks: each thread runs on its own connection and
# its own transaction, so the partial unique index (one active cart/user), the
# receipt unique index and SELECT ... FOR UPDATE on the cart row are what
# actually arbitrate. Transactional fixtures are off for that reason.
RSpec.describe ShoppingCarts::SessionReconciler, 'under concurrency', type: :model do
  self.use_transactional_tests = false

  CART_TABLES = %w[cart_session_imports shopping_cart_items shopping_carts].freeze

  def assert_isolated_test_database!
    db = ActiveRecord::Base.connection.current_database
    raise "refusing to truncate outside the test environment (#{Rails.env})" unless Rails.env.test?
    raise "refusing to truncate #{db}" if db.include?('development') || db.include?('production')
  end

  def clean!
    assert_isolated_test_database!
    ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{CART_TABLES.join(', ')} RESTART IDENTITY CASCADE")
    Product.where(id: @product_ids.to_a).find_each(&:destroy!) if @product_ids
    User.where(id: @user_ids.to_a).find_each(&:destroy!) if @user_ids
  end

  before do
    clean!
    @user_ids = Set.new
    @product_ids = Set.new
  end

  after { clean! }

  def new_user
    create(:user).tap { |u| @user_ids << u.id }
  end

  def new_product
    create(:product, skip_seed_inventory: true).tap { |p| @product_ids << p.id }
  end

  # Every thread holds its own connection and reaches the barrier before any
  # of them starts, so the requests overlap as tightly as the scheduler
  # allows. The pool has RAILS_MAX_THREADS (5) connections and the example's
  # own thread holds one, so at most 4 threads can hold one simultaneously;
  # more than that would wait on each other forever. The pops time out so a
  # mistake fails instead of hanging the suite.
  MAX_PARALLEL = 4
  BARRIER_TIMEOUT = 15

  def run_in_parallel(count)
    raise ArgumentError, "at most #{MAX_PARALLEL} parallel threads" if count > MAX_PARALLEL

    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          raise 'barrier start timed out' if start.pop(timeout: BARRIER_TIMEOUT).nil?

          outcomes << [:ok, yield(index)]
        rescue StandardError => e
          outcomes << [:error, e]
        end
      end
    end
    count.times { raise 'barrier ready timed out' if ready.pop(timeout: BARRIER_TIMEOUT).nil? }
    count.times { start << true }
    threads.each { |t| t.join(BARRIER_TIMEOUT * 2) or raise 'thread did not finish' }
    count.times.map { outcomes.pop(timeout: 1) or raise 'missing outcome' }
  end

  def reconcile(user, session_cart, session_id)
    described_class.call(user: user, session_cart: session_cart, session_id: session_id)
  end

  def quantities(cart)
    cart.shopping_cart_items.reload.to_h { |i| [[i.product_reference, i.condition], i.quantity] }
  end

  it 'applies the SAME import (same user, same key, same payload) exactly once across concurrent requests' do
    user = new_user
    product = new_product
    session_id = SecureRandom.hex(16)
    session_cart = { product.id.to_s => { 'brand_new' => 2 } }

    outcomes = run_in_parallel(4) { reconcile(user, session_cart, session_id) }

    errors = outcomes.select { |kind, _| kind == :error }.map(&:last)
    expect(errors).to be_empty, errors.map(&:full_message).join("\n")
    statuses = outcomes.map { |_, r| r.status }
    expect(statuses.count(:imported)).to eq(1)
    expect(statuses - %i[imported reused]).to be_empty

    expect(ShoppingCart.count).to eq(1)
    expect(CartSessionImport.count).to eq(1)
    cart = ShoppingCart.sole
    expect(quantities(cart)).to eq([product.id, 'brand_new'] => 2)
    expect(outcomes.map { |_, r| r.session_cart }.uniq).to eq([{ product.id.to_s => { 'brand_new' => 2 } }])
  end

  it 'applies the same import exactly once even when the first writer is slow inside its transaction' do
    user = new_user
    product = new_product
    session_id = SecureRandom.hex(16)
    session_cart = { product.id.to_s => { 'brand_new' => 2 } }
    first_inside = Queue.new

    allow_any_instance_of(described_class).to receive(:merge_lines!).and_wrap_original do |m, *args, **kwargs, &blk|
      if Thread.current[:slow_writer]
        first_inside << true
        sleep 0.5 # keep the receipt uncommitted while the second request arrives
      end
      m.call(*args, **kwargs, &blk)
    end

    outcomes = run_in_parallel(2) do |index|
      if index.zero?
        Thread.current[:slow_writer] = true
        reconcile(user, session_cart, session_id)
      else
        raise 'first writer never entered its transaction' if first_inside.pop(timeout: 10).nil?

        reconcile(user, session_cart, session_id)
      end
    end

    expect(outcomes.map(&:first)).to all(eq(:ok))
    expect(outcomes.map { |_, r| r.status }).to contain_exactly(:imported, :reused)
    expect(ShoppingCart.count).to eq(1)
    expect(CartSessionImport.count).to eq(1)
    expect(quantities(ShoppingCart.sole)).to eq([product.id, 'brand_new'] => 2)
  end

  it 'creates exactly one active cart when several first imports race' do
    user = new_user
    product = new_product
    keys = Array.new(4) { SecureRandom.hex(16) }

    outcomes = run_in_parallel(4) { |i| reconcile(user, { product.id.to_s => { 'brand_new' => 1 } }, keys[i]) }

    expect(outcomes.map(&:first)).to all(eq(:ok))
    expect(outcomes.map { |_, r| r.status }).to all(eq(:imported))
    expect(ShoppingCart.count).to eq(1)
    expect(ShoppingCart.sole.status).to eq('active')
    expect(CartSessionImport.count).to eq(4)
    expect(quantities(ShoppingCart.sole)).to eq([product.id, 'brand_new'] => 4)
  end

  it 'incorporates two browsers of the same user exactly once each, with no lost update' do
    user = new_user
    a = new_product
    b = new_product
    key_a = SecureRandom.hex(16)
    key_b = SecureRandom.hex(16)
    payload_a = { a.id.to_s => { 'brand_new' => 2 }, b.id.to_s => { 'misb' => 1 } }
    payload_b = { a.id.to_s => { 'brand_new' => 1, 'loose' => 1 } }

    outcomes = run_in_parallel(2) { |i| i.zero? ? reconcile(user, payload_a, key_a) : reconcile(user, payload_b, key_b) }

    expect(outcomes.map(&:first)).to all(eq(:ok))
    expect(outcomes.map { |_, r| r.status }).to all(eq(:imported))
    expect(ShoppingCart.count).to eq(1)
    expect(CartSessionImport.count).to eq(2)
    expect(quantities(ShoppingCart.sole)).to eq(
      [a.id, 'brand_new'] => 3, [a.id, 'loose'] => 1, [b.id, 'misb'] => 1
    )

    # Each browser retrying afterwards is recognised and applies nothing.
    expect(reconcile(user, payload_a, key_a).status).to eq(:reused)
    expect(reconcile(user, payload_b, key_b).status).to eq(:reused)
    expect(quantities(ShoppingCart.sole)).to eq(
      [a.id, 'brand_new'] => 3, [a.id, 'loose'] => 1, [b.id, 'misb'] => 1
    )
    expect(CartSessionImport.count).to eq(2)
  end

  it 'never produces duplicate ShoppingCartItem rows when overlapping lines are inserted concurrently' do
    user = new_user
    product = new_product
    keys = Array.new(4) { SecureRandom.hex(16) }

    outcomes = run_in_parallel(4) { |i| reconcile(user, { product.id.to_s => { 'misb' => 1 } }, keys[i]) }

    expect(outcomes.map(&:first)).to all(eq(:ok))
    expect(ShoppingCartItem.where(product_reference: product.id, condition: 'misb').count).to eq(1)
    expect(quantities(ShoppingCart.sole)).to eq([product.id, 'misb'] => 4)
  end
end
