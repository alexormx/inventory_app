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
    expect { cart.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
