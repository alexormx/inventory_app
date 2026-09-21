# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CartInventoryHold do
  let(:user)      { create(:user) }
  let(:cart)      { ShoppingCart.create!(user: user, status: 'active', last_activity_at: Time.current) }
  let(:product)   { create(:product, skip_seed_inventory: true) }
  let(:location)  { create(:inventory_location) }
  let(:inventory) do
    create(:inventory, product: product, status: :available, inventory_location: location)
  end
  let(:cart_item) do
    cart.shopping_cart_items.create!(
      product: product, product_reference: product.id,
      condition: :brand_new, quantity: 1, product_name_snapshot: product.product_name
    )
  end

  def hold(expires_at: CartInventoryHold::HOLD_DURATION.from_now, item: cart_item, inv: inventory)
    described_class.create!(
      shopping_cart: cart, inventory: inv, shopping_cart_item: item, expires_at: expires_at
    )
  end

  describe 'associations' do
    it 'belongs to a shopping cart, an inventory row and optionally a cart item' do
      record = hold

      expect(record.shopping_cart).to eq(cart)
      expect(record.inventory).to eq(inventory)
      expect(record.shopping_cart_item).to eq(cart_item)
    end

    it 'allows a null shopping_cart_item' do
      expect { hold(item: nil) }.not_to raise_error
    end

    it 'requires a shopping cart' do
      record = described_class.new(inventory: inventory, expires_at: 1.hour.from_now)
      expect(record).not_to be_valid
    end

    it 'requires an inventory row' do
      record = described_class.new(shopping_cart: cart, expires_at: 1.hour.from_now)
      expect(record).not_to be_valid
    end
  end

  describe 'expires_at' do
    it 'is required' do
      record = described_class.new(shopping_cart: cart, inventory: inventory)
      expect(record).not_to be_valid
      expect(record.errors[:expires_at]).to be_present
    end

    it 'is rejected by the database when null' do
      expect do
        described_class.connection.execute(
          "INSERT INTO cart_inventory_holds (shopping_cart_id, inventory_id, created_at, updated_at) " \
          "VALUES (#{cart.id}, #{inventory.id}, NOW(), NOW())"
        )
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe 'HOLD_DURATION' do
    it 'is four hours, defined once' do
      expect(described_class::HOLD_DURATION).to eq(4.hours)
    end
  end

  describe 'active / expired' do
    it 'treats a future expiry as active' do
      record = hold(expires_at: 10.minutes.from_now)

      expect(described_class.active).to include(record)
      expect(described_class.expired).not_to include(record)
      expect(record).to be_active
      expect(record).not_to be_expired
    end

    it 'treats a past expiry as expired even though the row still exists' do
      record = hold(expires_at: 1.second.ago)

      expect(described_class.expired).to include(record)
      expect(described_class.active).not_to include(record)
      expect(record).to be_expired
      expect(described_class.count).to eq(1)
    end

    it 'becomes inactive the moment expires_at passes, with no cleanup run' do
      record = hold(expires_at: 5.minutes.from_now)
      expect(described_class.active).to include(record)

      # Move the row's own deadline into the past rather than Ruby's clock:
      # the scopes are judged by DATABASE time, which travel_to cannot move.
      # Nothing deletes the row.
      record.update_columns(expires_at: 1.second.ago)

      expect(described_class.active).not_to include(record)
      expect(described_class.expired).to include(record)
      expect(described_class.where(id: record.id)).to exist
    end

    # The distinguishing case for clock_timestamp() over CURRENT_TIMESTAMP.
    # CURRENT_TIMESTAMP freezes at transaction start, so a deadline that falls
    # DURING a long transaction would still read as active and a slow checkout
    # could consume a lapsed hold. clock_timestamp() advances, so the boundary
    # is real wall-clock time even mid-transaction.
    it 'sees a deadline that passes during an open transaction' do
      record = nil

      described_class.transaction do
        record = hold(expires_at: 0.2.seconds.from_now)
        expect(described_class.active).to include(record)

        sleep 0.4

        # Still the same transaction: CURRENT_TIMESTAMP has not moved, but the
        # hold is genuinely past its deadline and must read as expired.
        expect(described_class.active).not_to include(record)
        expect(described_class.expired).to include(record)
      end
    end

    # The scopes decide ownership on database time; the Ruby predicates are a
    # convenience for an already-loaded record. Documented so the split is a
    # deliberate contract rather than a surprise.
    it 'judges scopes on database time and predicates on ruby time' do
      record = hold(expires_at: 5.minutes.from_now)

      travel_to(6.minutes.from_now) do
        expect(record).to be_expired
        # The authoritative scope still reads the database clock.
        expect(described_class.active).to include(record)
      end
    end
  end

  describe 'scopes' do
    it 'filters by cart and by cart item' do
      record = hold

      expect(described_class.for_cart(cart)).to include(record)
      expect(described_class.for_cart_item(cart_item)).to include(record)
    end
  end

  describe 'one hold per physical inventory row' do
    it 'refuses a second hold row for the same inventory' do
      hold
      other_cart = ShoppingCart.create!(
        user: create(:user), status: 'active', last_activity_at: Time.current
      )

      expect do
        described_class.create!(
          shopping_cart: other_cart, inventory: inventory, expires_at: 1.hour.from_now
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'foreign keys' do
    it 'is removed when its cart is deleted' do
      record = hold
      cart.shopping_cart_items.delete_all
      cart.destroy!

      expect(described_class.where(id: record.id)).to be_empty
    end

    it 'is removed when its inventory row is deleted' do
      record = hold
      inventory.destroy!

      expect(described_class.where(id: record.id)).to be_empty
    end

    it 'survives cart-item deletion with a null cart_item, as a defensive backstop' do
      record = hold
      ShoppingCartItem.where(id: cart_item.id).delete_all

      expect(record.reload.shopping_cart_item_id).to be_nil
    end
  end
end
