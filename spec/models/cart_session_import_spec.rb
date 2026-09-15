# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CartSessionImport, type: :model do
  it 'belongs to its originating shopping cart' do
    cart = create(:shopping_cart, :owned)
    import = create(:cart_session_import, shopping_cart: cart)

    expect(import.shopping_cart).to eq(cart)
  end

  it 'requires a unique import_key_digest' do
    create(:cart_session_import, import_key_digest: 'dup-key')
    duplicate = build(:cart_session_import, import_key_digest: 'dup-key')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:import_key_digest]).to be_present
  end

  it 'enforces the unique import_key_digest at the database level' do
    create(:cart_session_import, import_key_digest: 'dup-key-db')
    duplicate = build(:cart_session_import, import_key_digest: 'dup-key-db')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects a payload larger than the bounded size at the database level' do
    oversized = { 'blob' => 'x' * 9000 }
    import = build(:cart_session_import, source_payload: oversized)

    expect { import.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /cart_session_imports_payload_bounded/)
  end

  it 'accepts a realistically-sized cart payload' do
    import = build(:cart_session_import, source_payload: { '42' => { 'brand_new' => 3 }, '99' => { 'loose' => 1 } })

    expect(import).to be_valid
  end

  it 'restricts destroying the referenced shopping cart at the Rails level' do
    cart = create(:shopping_cart, :owned)
    create(:cart_session_import, shopping_cart: cart)

    expect(cart.destroy).to be false
    expect(cart.errors[:base]).to be_present
    expect(ShoppingCart.exists?(cart.id)).to be true
  end

  it 'restricts deleting the referenced shopping cart at the database level' do
    cart = create(:shopping_cart, :owned)
    create(:cart_session_import, shopping_cart: cart)

    # .delete (unlike .destroy) skips callbacks/dependent options entirely,
    # so this exercises the DB-level ON DELETE RESTRICT constraint directly.
    # Depending on the Postgres version, a RESTRICT violation on delete may
    # surface as the specific ActiveRecord::InvalidForeignKey or the more
    # general ActiveRecord::StatementInvalid it inherits from - assert the
    # parent class so the test isn't coupled to that version difference.
    expect { cart.delete }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'requires a source payload digest' do
    import = build(:cart_session_import, source_payload_digest: nil)

    expect(import).not_to be_valid
    expect { import.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it 'accepts exactly 8192 bytes of serialized jsonb' do
    # PostgreSQL renders this single-key object with 12 bytes of JSON syntax.
    import = build(:cart_session_import, source_payload: { 'blob' => 'x' * (8192 - 12) })

    expect { import.save! }.not_to raise_error
  end

  it 'rejects one byte beyond the serialized jsonb limit' do
    import = build(:cart_session_import, source_payload: { 'blob' => 'x' * (8193 - 12) })

    expect { import.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /cart_session_imports_payload_bounded/)
  end

  it 'rolls back item destruction when an import receipt prevents cart destruction' do
    cart = create(:shopping_cart)
    item = create(:shopping_cart_item, shopping_cart: cart)
    create(:cart_session_import, shopping_cart: cart)

    expect(cart.destroy).to be false
    expect(ShoppingCartItem.exists?(item.id)).to be true
  end
end
