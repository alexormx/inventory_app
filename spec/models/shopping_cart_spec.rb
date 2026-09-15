# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCart, type: :model do
  describe 'active carts' do
    it 'is valid as an anonymous cart' do
      cart = build(:shopping_cart, :anonymous)

      expect(cart).to be_valid
    end

    it 'is valid as an owned (authenticated) cart' do
      cart = build(:shopping_cart, :owned)

      expect(cart).to be_valid
    end

    it 'enforces at most one active cart per user at the database level' do
      user = create(:user)
      create(:shopping_cart, user: user, status: 'active')
      duplicate = build(:shopping_cart, user: user, status: 'active')

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_shopping_carts_on_user_id_when_active/)
    end

    it 'allows multiple terminal carts for the same user' do
      user = create(:user)
      create(:shopping_cart, :converted, user: user)
      second = build(:shopping_cart, :converted, user: user)
      second.sale_order = create(:sale_order, user: user)

      expect(second).to be_valid
      expect { second.save! }.not_to raise_error
    end
  end

  describe 'anonymous_token_digest uniqueness' do
    it 'enforces a unique non-null anonymous token digest at the database level' do
      digest = SecureRandom.hex(32)
      create(:shopping_cart, :anonymous, anonymous_token_digest: digest)
      duplicate = build(:shopping_cart, :anonymous, anonymous_token_digest: digest)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows multiple carts with a nil anonymous_token_digest' do
      create(:shopping_cart, :owned, anonymous_token_digest: nil)
      second = build(:shopping_cart, :owned, anonymous_token_digest: nil)

      expect { second.save! }.not_to raise_error
    end
  end

  describe 'sale_order conversion uniqueness' do
    it 'enforces a unique sale_order_id at the database level' do
      order = create(:sale_order)
      create(:shopping_cart, :converted, sale_order: order)
      duplicate = build(:shopping_cart, :converted, sale_order: order)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'lifecycle invariants' do
    it 'rejects an active cart that carries a sale_order_id' do
      cart = build(:shopping_cart, status: 'active', sale_order: create(:sale_order))

      expect(cart).not_to be_valid
      expect(cart.errors[:sale_order_id]).to be_present
    end

    it 'rejects an active cart that carries converted_at' do
      cart = build(:shopping_cart, status: 'active', converted_at: Time.current)

      expect(cart).not_to be_valid
      expect(cart.errors[:converted_at]).to be_present
    end

    it 'rejects an active cart that carries closed_at' do
      cart = build(:shopping_cart, status: 'active', closed_at: Time.current)

      expect(cart).not_to be_valid
      expect(cart.errors[:closed_at]).to be_present
    end

    it 'rejects an active cart that carries merged_into_cart_id' do
      target = create(:shopping_cart, :owned)
      cart = build(:shopping_cart, status: 'active', merged_into_cart: target)

      expect(cart).not_to be_valid
      expect(cart.errors[:merged_into_cart_id]).to be_present
    end

    it 'rejects the database-level invariant too when validations are bypassed' do
      cart = build(:shopping_cart, status: 'active', sale_order: create(:sale_order))

      expect { cart.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /shopping_carts_lifecycle_invariants/)
    end

    it 'requires sale_order_id, converted_at and closed_at for a converted cart' do
      cart = build(:shopping_cart, status: 'converted')

      expect(cart).not_to be_valid
      expect(cart.errors[:sale_order_id]).to be_present
      expect(cart.errors[:converted_at]).to be_present
      expect(cart.errors[:closed_at]).to be_present
    end

    it 'accepts a fully-formed converted cart' do
      cart = build(:shopping_cart, :converted)

      expect(cart).to be_valid
    end

    it 'requires merged_into_cart_id and closed_at for a merged cart' do
      cart = build(:shopping_cart, status: 'merged')

      expect(cart).not_to be_valid
      expect(cart.errors[:merged_into_cart_id]).to be_present
      expect(cart.errors[:closed_at]).to be_present
    end

    it 'accepts a fully-formed merged cart' do
      cart = build(:shopping_cart, :merged)

      expect(cart).to be_valid
    end

    it 'rejects a cart merged into itself' do
      cart = create(:shopping_cart, :owned)
      cart.status = 'merged'
      cart.closed_at = Time.current
      cart.merged_into_cart_id = cart.id

      expect(cart).not_to be_valid
      expect(cart.errors[:merged_into_cart_id]).to include('cannot merge a cart into itself')
    end

    it 'rejects self-merge at the database level too' do
      cart = create(:shopping_cart, :owned)

      expect do
        ShoppingCart.where(id: cart.id).update_all(status: 'merged', closed_at: Time.current,
                                                   merged_into_cart_id: cart.id)
      end.to raise_error(ActiveRecord::StatementInvalid, /shopping_carts_no_self_merge/)
    end

    it 'requires closed_at for a cleared cart' do
      cart = build(:shopping_cart, status: 'cleared')

      expect(cart).not_to be_valid
      expect(cart.errors[:closed_at]).to be_present
    end

    it 'accepts a fully-formed cleared cart' do
      cart = build(:shopping_cart, :cleared)

      expect(cart).to be_valid
    end

    it 'does not allow a terminal owned cart to retain an anonymous token digest' do
      cart = build(:shopping_cart, :cleared, anonymous_token_digest: SecureRandom.hex(32))

      expect(cart).not_to be_valid
      expect(cart.errors[:anonymous_token_digest]).to be_present
    end
  end

  describe 'associations' do
    it 'restricts destroying a user with shopping cart history' do
      user = create(:user)
      create(:shopping_cart, :converted, user: user)

      expect { user.destroy }.not_to change(User, :count)
      expect(user.errors[:base]).to be_present
    end
  end

  describe 'lifecycle matrix under validation bypass' do
    { active: %i[sale_order_id converted_at closed_at merged_into_cart_id],
      converted: %i[sale_order_id converted_at closed_at],
      merged: %i[merged_into_cart_id closed_at],
      cleared: %i[closed_at] }.each do |status, fields|
      it "persists a valid #{status} cart" do
        cart = build(:shopping_cart, *(status == :active ? [] : [status]))

        expect(cart).to be_valid
        expect { cart.save!(validate: false) }.not_to raise_error
      end

      fields.each do |field|
        it "rejects #{status} with an invalid #{field} in Rails and PostgreSQL" do
          cart = build(:shopping_cart, *(status == :active ? [] : [status]))
          cart[field] = if status != :active
                          nil
                        elsif field == :sale_order_id
                          create(:sale_order).id
                        elsif field == :merged_into_cart_id
                          create(:shopping_cart).id
                        else
                          Time.current
                        end

          expect(cart).not_to be_valid
          expect(cart.errors[field]).to be_present
          expect { cart.save!(validate: false) }
            .to raise_error(ActiveRecord::StatementInvalid, /shopping_carts_lifecycle_invariants/)
        end
      end
    end

    %i[converted merged cleared].each do |status|
      ['digest', ''].each do |digest|
        it "rejects #{status} with token #{digest.inspect} in Rails and PostgreSQL" do
          cart = build(:shopping_cart, status, anonymous_token_digest: digest)

          expect(cart).not_to be_valid
          expect(cart.errors[:anonymous_token_digest]).to be_present
          expect { cart.save!(validate: false) }
            .to raise_error(ActiveRecord::StatementInvalid, /shopping_carts_lifecycle_invariants/)
        end
      end
    end

    it 'rejects an unknown lifecycle status in Rails and PostgreSQL' do
      cart = build(:shopping_cart, status: 'unknown')

      expect(cart).not_to be_valid
      expect { cart.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /shopping_carts_lifecycle_invariants/)
    end
  end

  describe 'history and locking' do
    it 'restricts destroying a user whose only dependency is a shopping cart' do
      user = create(:user)
      create(:shopping_cart, :cleared, user: user)

      expect(user.destroy).to be false
      expect(user.errors[:base]).to be_present
      expect(User.exists?(user.id)).to be true
    end

    it 'restricts deleting a cart owner without callbacks' do
      user = create(:user)
      create(:shopping_cart, user: user)

      expect { user.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'protects the converted sale order from deletion' do
      cart = create(:shopping_cart, :converted)

      expect { cart.sale_order.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'protects a merge destination from deletion' do
      cart = create(:shopping_cart, :merged)

      expect { cart.merged_into_cart.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it 'rejects an update from a stale cart instance' do
      cart = create(:shopping_cart)
      stale = described_class.find(cart.id)
      cart.update!(last_activity_at: 1.minute.from_now)

      expect(cart.lock_version).to eq(1)
      expect { stale.update!(status: 'cleared', closed_at: Time.current) }
        .to raise_error(ActiveRecord::StaleObjectError)
      expect(cart.reload.status).to eq('active')
    end

    it 'rejects reactivating a historical cart when the owner already has an active cart' do
      active = create(:shopping_cart, :owned)
      historical = create(:shopping_cart, :cleared, user: active.user)

      expect { historical.update_columns(status: 'active', closed_at: nil) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_shopping_carts_on_user_id_when_active/)
    end
  end
end
