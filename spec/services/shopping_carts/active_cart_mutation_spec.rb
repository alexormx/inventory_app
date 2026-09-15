# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ActiveCartMutation do
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:other) { create(:product, skip_seed_inventory: true) }

  def lines
    ShoppingCartItem.pluck(:product_reference, :condition, :quantity).map { |r, c, q| [r, c, q] }.sort
  end

  describe '.add' do
    it 'creates exactly one active cart on the first add and reuses it' do
      first = described_class.add(user: user, product: product, condition: 'brand_new')
      second = described_class.add(user: user, product: product, condition: 'brand_new')

      expect(first).to be_ok
      expect(second).to be_ok
      expect(second.cart).to eq(first.cart)
      expect(second.quantity).to eq(2)
      expect(ShoppingCart.count).to eq(1)
      expect(lines).to eq([[product.id, 'brand_new', 2]])
      expect(second.session_cart).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(first.cart.reload.last_activity_at).to be_within(5.seconds).of(Time.current)
    end

    it 'keeps conditions of the same product as independent lines' do
      described_class.add(user: user, product: product, condition: 'brand_new')
      described_class.add(user: user, product: product, condition: 'misb')

      expect(lines).to eq([[product.id, 'brand_new', 1], [product.id, 'misb', 1]])
    end

    it 'refuses to exceed the storefront cap without writing anything' do
      Cart::MAX_NEW_ITEMS_PER_PRODUCT.times { described_class.add(user: user, product: product, condition: 'brand_new') }

      result = described_class.add(user: user, product: product, condition: 'brand_new')

      expect(result.status).to eq(:limit_exceeded)
      expect(lines).to eq([[product.id, 'brand_new', Cart::MAX_NEW_ITEMS_PER_PRODUCT]])
      expect(described_class.add(user: user, product: product, condition: 'misb').status).to eq(:ok)
      expect(described_class.add(user: user, product: product, condition: 'misb').status).to eq(:limit_exceeded)
    end

    it 'does not clamp an imported line that already sits above the cap, and refuses to grow it' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 6)

      expect(described_class.add(user: user, product: product, condition: 'brand_new').status).to eq(:limit_exceeded)
      expect(lines).to eq([[product.id, 'brand_new', 6]])
    end

    it 'does not reserve inventory or touch orders' do
      seeded = create(:product)
      before = [Inventory.pluck(:id, :status, :sale_order_id).sort, SaleOrder.count]

      described_class.add(user: user, product: seeded, condition: 'brand_new')

      expect([Inventory.pluck(:id, :status, :sale_order_id).sort, SaleOrder.count]).to eq(before)
    end
  end

  describe '.set_quantity' do
    it 'persists the exact intended quantity' do
      described_class.add(user: user, product: product, condition: 'brand_new')

      result = described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 3)

      expect(result).to be_ok
      expect(lines).to eq([[product.id, 'brand_new', 3]])
    end

    it 'creates the line (and the cart) when it does not exist yet' do
      result = described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 2)

      expect(result).to be_ok
      expect(lines).to eq([[product.id, 'brand_new', 2]])
    end

    it 'refuses a quantity above the cap' do
      described_class.add(user: user, product: product, condition: 'brand_new')

      result = described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 4)

      expect(result.status).to eq(:limit_exceeded)
      expect(lines).to eq([[product.id, 'brand_new', 1]])
    end

    it 'lets the customer lower an over-cap imported line to the cap' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 6)

      expect(described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 3)).to be_ok
      expect(lines).to eq([[product.id, 'brand_new', 3]])
    end

    it 'treats zero or negative as a removal' do
      described_class.add(user: user, product: product, condition: 'brand_new')

      expect(described_class.set_quantity(user: user, product: product, condition: 'brand_new', quantity: 0)).to be_ok
      expect(lines).to eq([])
    end
  end

  describe '.remove' do
    before do
      described_class.add(user: user, product: product, condition: 'brand_new')
      described_class.add(user: user, product: product, condition: 'misb')
      described_class.add(user: user, product: other, condition: 'brand_new')
    end

    it 'removes one condition of a product' do
      expect(described_class.remove(user: user, product: product, condition: 'misb')).to be_ok
      expect(lines).to contain_exactly([other.id, 'brand_new', 1], [product.id, 'brand_new', 1])
    end

    it 'removes every condition of a product when none is given' do
      expect(described_class.remove(user: user, product: product)).to be_ok
      expect(lines).to eq([[other.id, 'brand_new', 1]])
    end

    it 'leaves the cart ACTIVE and empty after the last line goes' do
      described_class.remove(user: user, product: product)
      result = described_class.remove(user: user, product: other)

      expect(result).to be_ok
      expect(result.session_cart).to eq({})
      expect(ShoppingCart.sole.status).to eq('active')
      expect(ShoppingCart.sole.shopping_cart_items.count).to eq(0)
    end

    it 'is a no-op without an active cart and never creates one' do
      result = described_class.remove(user: create(:user), product: product)

      expect(result).to be_ok
      expect(result.cart).to be_nil
      expect(ShoppingCart.count).to eq(1)
    end
  end

  describe '.clear' do
    it 'deletes every line and keeps the cart active' do
      described_class.add(user: user, product: product, condition: 'brand_new')
      described_class.add(user: user, product: other, condition: 'loose')

      expect(described_class.clear(user: user)).to be_ok
      expect(lines).to eq([])
      expect(ShoppingCart.sole.status).to eq('active')
    end
  end

  describe 'terminal carts' do
    it 'never writes into a cart that became converted; the add lands in a fresh active cart' do
      converted = create(:shopping_cart, :converted, user: user)

      result = described_class.add(user: user, product: product, condition: 'brand_new')

      expect(result).to be_ok
      expect(result.cart).not_to eq(converted)
      expect(result.cart.status).to eq('active')
      expect(converted.reload.shopping_cart_items.count).to eq(0)
      expect(user.shopping_carts.count).to eq(2)
    end

    it 'retries when the cart stops being active between lookup and lock' do
      poisoned = false
      allow_any_instance_of(ShoppingCart).to receive(:lock!).and_wrap_original do |m, *args, **kwargs, &blk|
        cart = m.call(*args, **kwargs, &blk)
        unless poisoned
          poisoned = true
          cart.status = 'converted'
        end
        cart
      end

      result = described_class.add(user: user, product: product, condition: 'brand_new')

      expect(result).to be_ok
      expect(lines).to eq([[product.id, 'brand_new', 1]])
      expect(ShoppingCart.count).to eq(1)
    end

    it 'gives up with :retry_exhausted instead of looping or writing' do
      allow(ShoppingCarts::ActiveCartResolver).to receive(:find_or_create!)
        .and_raise(ActiveRecord::RecordNotUnique, 'index_shopping_carts_on_user_id_when_active')

      result = described_class.add(user: user, product: product, condition: 'brand_new')

      expect(result.status).to eq(:retry_exhausted)
      expect(ShoppingCartItem.count).to eq(0)
    end
  end

  describe 'failure before commit' do
    it 'rolls back the cart creation together with the line' do
      allow(ShoppingCartItem).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { described_class.add(user: user, product: product, condition: 'brand_new') }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect(ShoppingCart.count).to eq(0)
      expect(ShoppingCartItem.count).to eq(0)
    end
  end
end
