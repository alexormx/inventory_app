# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::SessionReconciler do
  let(:user) { create(:user) }
  let(:session_id) { SecureRandom.hex(16) }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:other_product) { create(:product, skip_seed_inventory: true) }

  def reconcile(session_cart, user: self.user, session_id: self.session_id, marker: nil)
    described_class.call(user: user, session_cart: session_cart, session_id: session_id, reconciled_marker: marker)
  end

  def quantities(cart)
    cart.shopping_cart_items.reload.to_h { |i| [[i.product_reference, i.condition], i.quantity] }
  end

  def expect_nothing_persisted
    expect(ShoppingCart.count).to eq(0)
    expect(ShoppingCartItem.count).to eq(0)
    expect(CartSessionImport.count).to eq(0)
  end

  describe 'reconciliation matrix' do
    it 'CASE A: no persistent cart + empty session is a no-op that creates nothing' do
      [nil, {}, { product.id.to_s => { 'brand_new' => 0 } }].each do |empty|
        result = reconcile(empty)
        expect(result.status).to eq(:noop)
        expect(result).to be_success
        expect(result).not_to be_hydrate
      end
      expect_nothing_persisted
    end

    it 'CASE B: no persistent cart + session cart creates one active cart, imports and records a receipt' do
      session_cart = { product.id.to_s => { 'brand_new' => 2, 'misb' => 1 }, other_product.id.to_s => { 'loose' => 1 } }

      result = reconcile(session_cart)

      expect(result.status).to eq(:imported)
      expect(result).to be_hydrate
      cart = result.cart
      expect(cart.user).to eq(user)
      expect(cart.status).to eq('active')
      expect(quantities(cart)).to eq(
        [product.id, 'brand_new'] => 2, [product.id, 'misb'] => 1, [other_product.id, 'loose'] => 1
      )
      expect(cart.shopping_cart_items.pluck(:product_id, :product_name_snapshot))
        .to include([product.id, product.product_name])

      receipt = result.receipt
      expect(receipt).to be_persisted
      expect(receipt.shopping_cart).to eq(cart)
      expect(receipt.import_key_digest).to eq(ShoppingCarts::ImportIdentity.new(session_id).digest)
      expect(receipt.source_payload_digest).to eq(ShoppingCarts::SessionCartNormalizer.call(session_cart).digest)
      expect(receipt.source_payload).to eq(ShoppingCarts::SessionCartNormalizer.call(session_cart).payload)

      expect(result.session_cart).to eq(
        product.id.to_s => { 'brand_new' => 2, 'misb' => 1 }, other_product.id.to_s => { 'loose' => 1 }
      )
      expect(result.details).to include(lines_created: 3, lines_combined: 0, over_business_limit: 0)
    end

    it 'CASE C: persistent cart + empty session restores the cart into the session without duplicating or recording' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 2)

      result = reconcile({})

      expect(result.status).to eq(:rehydrated)
      expect(result.session_cart).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(0)
      expect(ShoppingCart.count).to eq(1)
    end

    it 'CASE D: persistent cart + session cart combines matching lines and preserves disjoint ones' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'brand_new', quantity: 1)
      create(:shopping_cart_item, shopping_cart: cart, product: product, condition: 'misb', quantity: 1)
      create(:shopping_cart_item, shopping_cart: cart, product: other_product, condition: 'brand_new', quantity: 2)
      third = create(:product, skip_seed_inventory: true)

      result = reconcile({
        product.id.to_s => { 'brand_new' => 2, 'loose' => 1 }, # overlap + new condition of same product
        third.id.to_s => { 'brand_new' => 1 }                  # disjoint
      })

      expect(result.status).to eq(:imported)
      expect(result.cart).to eq(cart)
      expect(quantities(cart)).to eq(
        [product.id, 'brand_new'] => 3,       # combined
        [product.id, 'misb'] => 1,            # untouched persistent line
        [product.id, 'loose'] => 1,           # same product, independent condition
        [other_product.id, 'brand_new'] => 2, # untouched persistent line
        [third.id, 'brand_new'] => 1          # disjoint session line
      )
      expect(result.session_cart).to eq(
        product.id.to_s => { 'brand_new' => 3, 'misb' => 1, 'loose' => 1 },
        other_product.id.to_s => { 'brand_new' => 2 },
        third.id.to_s => { 'brand_new' => 1 }
      )
      expect(ShoppingCart.count).to eq(1)
      expect(result.details).to include(lines_created: 2, lines_combined: 1)
    end
  end

  describe 'quantity semantics' do
    it 'combines beyond the storefront purchase cap without clamping and surfaces it' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: Cart::MAX_NEW_ITEMS_PER_PRODUCT)

      result = reconcile({ product.id.to_s => { 'brand_new' => Cart::MAX_NEW_ITEMS_PER_PRODUCT } })

      expect(result.status).to eq(:imported)
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => Cart::MAX_NEW_ITEMS_PER_PRODUCT * 2)
      expect(result.details[:over_business_limit]).to eq(1)
    end

    it 'fails the ENTIRE reconciliation atomically when a combined quantity exceeds the technical bound' do
      cart = create(:shopping_cart, user: user)
      big = create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 99_999)

      result = reconcile({
        other_product.id.to_s => { 'brand_new' => 1 }, # would be created first
        product.id.to_s => { 'brand_new' => 2 }        # overflows
      })

      expect(result.status).to eq(:quantity_overflow)
      expect(result).not_to be_success
      expect(result).not_to be_hydrate
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 99_999)
      expect(big.reload.quantity).to eq(99_999)
      expect(CartSessionImport.count).to eq(0)
      expect(ShoppingCart.count).to eq(1)
    end
  end

  describe 'exactly-once receipt semantics' do
    let(:session_cart) { { product.id.to_s => { 'brand_new' => 2 } } }

    it 'reuses the receipt on a retry with the same key and payload, never applying quantities twice' do
      first = reconcile(session_cart)
      second = reconcile(session_cart)

      expect(first.status).to eq(:imported)
      expect(second.status).to eq(:reused)
      expect(second.cart).to eq(first.cart)
      expect(second.receipt).to eq(first.receipt)
      expect(second.session_cart).to eq(first.session_cart)
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
      expect(ShoppingCart.count).to eq(1)
    end

    it 'survives a crash after DB commit but before the session was rewritten' do
      browser_session = { cart: session_cart.deep_dup }

      crashed = reconcile(browser_session[:cart])
      expect(crashed.status).to eq(:imported)
      # ... the process dies here: the cookie still carries the pre-import cart.

      retried = reconcile(browser_session[:cart])
      expect(retried.status).to eq(:reused)
      expect(retried).to be_hydrate
      browser_session[:cart] = retried.session_cart

      expect(browser_session[:cart]).to eq(product.id.to_s => { 'brand_new' => 2 })
      expect(quantities(crashed.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(ShoppingCartItem.count).to eq(1)
      expect(CartSessionImport.count).to eq(1)
      expect(ShoppingCart.count).to eq(1)
    end

    it 'rehydrates a reused receipt from the CURRENT active cart, not from history' do
      first = reconcile(session_cart)
      create(:shopping_cart_item, shopping_cart: first.cart, product: other_product, quantity: 1)

      expect(reconcile(session_cart).session_cart).to eq(
        product.id.to_s => { 'brand_new' => 2 }, other_product.id.to_s => { 'brand_new' => 1 }
      )
    end

    it 'refuses to reinterpret history when the same key arrives with a different payload' do
      first = reconcile(session_cart)

      result = reconcile({ product.id.to_s => { 'brand_new' => 5 } })

      expect(result.status).to eq(:payload_mismatch)
      expect(result).not_to be_success
      expect(result).not_to be_hydrate
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
      expect(first.receipt.reload.source_payload).to eq(product.id.to_s => { 'brand_new' => 2 })
    end

    it 'never lets another user consume a receipt, its cart, or re-apply its quantities' do
      first = reconcile(session_cart)
      intruder = create(:user)

      result = reconcile(session_cart, user: intruder, session_id: session_id)

      expect(result.status).to eq(:foreign_receipt)
      expect(result).not_to be_hydrate
      expect(result.cart).to be_nil
      expect(intruder.shopping_carts.count).to eq(0)
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
    end

    it 'does not import without a stable browser identity' do
      result = reconcile(session_cart, session_id: nil)

      expect(result.status).to eq(:missing_identity)
      expect_nothing_persisted
    end
  end

  describe 'malformed payloads' do
    it 'rejects the whole payload and touches nothing, even when a persistent cart exists' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 1)

      result = reconcile({ product.id.to_s => { 'brand_new' => 2 }, other_product.id.to_s => { 'brand_new' => 'x' } })

      expect(result.status).to eq(:invalid_payload)
      expect(result).not_to be_hydrate
      expect(result.details[:errors]).to be_present
      expect(quantities(cart)).to eq([product.id, 'brand_new'] => 1)
      expect(CartSessionImport.count).to eq(0)
    end
  end

  describe 'product edge cases' do
    it 'drops lines whose product no longer exists and imports the rest' do
      missing_id = product.id + 100_000

      result = reconcile({ product.id.to_s => { 'brand_new' => 1 }, missing_id.to_s => { 'brand_new' => 1 } })

      expect(result.status).to eq(:imported)
      expect(quantities(result.cart)).to eq([product.id, 'brand_new'] => 1)
      expect(result.details[:skipped_missing_products]).to eq(1)
      expect(result.receipt.source_payload.keys).to contain_exactly(product.id.to_s, missing_id.to_s)
    end

    it 'does not create an empty cart or a receipt when nothing is importable' do
      result = reconcile({ (product.id + 100_000).to_s => { 'brand_new' => 1 } })

      expect(result.status).to eq(:noop)
      expect(result.details[:skipped_missing_products]).to eq(1)
      expect_nothing_persisted
    end

    it 'rehydrates an existing cart when the session only references missing products' do
      cart = create(:shopping_cart, user: user)
      create(:shopping_cart_item, shopping_cart: cart, product: product, quantity: 1)

      result = reconcile({ (product.id + 100_000).to_s => { 'brand_new' => 1 } })

      expect(result.status).to eq(:rehydrated)
      expect(result.session_cart).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect(CartSessionImport.count).to eq(0)
    end

    it 'keeps inactive products, exactly as the storefront cart still shows them' do
      product.update!(status: 'inactive')

      result = reconcile({ product.id.to_s => { 'brand_new' => 1 } })

      expect(result.status).to eq(:imported)
      expect(result.session_cart).to eq(product.id.to_s => { 'brand_new' => 1 })
    end

    it 'leaves a line whose product was deleted after import out of the rehydrated session' do
      first = reconcile({ product.id.to_s => { 'brand_new' => 1 }, other_product.id.to_s => { 'brand_new' => 1 } })
      first.cart.shopping_cart_items.find_by(product_reference: other_product.id).update_column(:product_id, nil)

      result = reconcile({})

      expect(result.status).to eq(:rehydrated)
      expect(result.session_cart).to eq(product.id.to_s => { 'brand_new' => 1 })
      expect(first.cart.shopping_cart_items.count).to eq(2)
    end
  end

  describe 'failure injection' do
    let(:session_cart) { { product.id.to_s => { 'brand_new' => 1 }, other_product.id.to_s => { 'brand_new' => 1 } } }

    it 'rolls back the cart, every line and the receipt when the second line fails' do
      saves = 0
      allow_any_instance_of(ShoppingCartItem).to receive(:save!).and_wrap_original do |m, *args, **kwargs, &blk|
        saves += 1
        raise 'disk on fire' if saves == 2

        m.call(*args, **kwargs, &blk)
      end

      expect { reconcile(session_cart) }.to raise_error(RuntimeError, 'disk on fire')
      expect_nothing_persisted

      allow_any_instance_of(ShoppingCartItem).to receive(:save!).and_call_original
      expect(reconcile(session_cart).status).to eq(:imported)
      expect(ShoppingCartItem.count).to eq(2)
    end

    it 'rolls back the freshly created cart when the receipt cannot be written' do
      allow(CartSessionImport).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'receipt down')

      expect { reconcile(session_cart) }.to raise_error(ActiveRecord::StatementInvalid)
      expect_nothing_persisted
    end

    it 'never writes into a cart that stopped being active between lookup and lock, and retries' do
      # Model another writer closing the cart between our lookup and our
      # SELECT ... FOR UPDATE: the first reload observes a non-active row.
      poisoned = false
      allow_any_instance_of(ShoppingCart).to receive(:lock!).and_wrap_original do |m, *args, **kwargs, &blk|
        cart = m.call(*args, **kwargs, &blk)
        unless poisoned
          poisoned = true
          cart.status = 'cleared'
        end
        cart
      end

      result = reconcile(session_cart)

      expect(result.status).to eq(:imported)
      expect(result.cart.status).to eq('active')
      expect(ShoppingCart.count).to eq(1)
      expect(CartSessionImport.count).to eq(1)
      expect(result.cart.shopping_cart_items.count).to eq(2)
    end

    it 'gives up cleanly instead of looping when the race never resolves' do
      allow(ShoppingCarts::ActiveCartResolver).to receive(:find_or_create!)
        .and_raise(ActiveRecord::RecordNotUnique, 'index_shopping_carts_on_user_id_when_active')

      result = reconcile(session_cart)

      expect(result.status).to eq(:retry_exhausted)
      expect(result).not_to be_success
      expect_nothing_persisted
    end
  end

  describe 'after a hydration marker exists in the session' do
    let(:session_cart) { { product.id.to_s => { 'brand_new' => 2 } } }
    # Warden renews the session id on every authentication, so a later event
    # in the same browser session derives a DIFFERENT import key.
    let(:renewed_session_id) { SecureRandom.hex(16) }

    it 'carries a marker with every hydrating result and none with a no-op' do
      first = reconcile(session_cart)
      expect(first.session_marker).to eq(
        'cart_id' => first.cart.id, 'digest' => ShoppingCarts::SessionCartNormalizer.call(first.session_cart).digest
      )
      expect(reconcile(session_cart).session_marker).to eq(first.session_marker)   # reused
      expect(reconcile({}).session_marker).to eq(first.session_marker)             # rehydrated
      expect(reconcile({}, user: create(:user)).session_marker).to be_nil          # noop
    end

    it 'rehydrates instead of importing again when the session is unchanged since hydration' do
      first = reconcile(session_cart)

      again = reconcile(first.session_cart, marker: first.session_marker, session_id: renewed_session_id)

      expect(again.status).to eq(:rehydrated)
      expect(again.session_cart).to eq(first.session_cart)
      expect(again.session_marker).to eq(first.session_marker)
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
    end

    it 'refreshes the session with lines another browser imported meanwhile' do
      first = reconcile(session_cart)
      reconcile({ other_product.id.to_s => { 'misb' => 1 } }, session_id: SecureRandom.hex(16))

      again = reconcile(first.session_cart, marker: first.session_marker, session_id: renewed_session_id)

      expect(again.status).to eq(:rehydrated)
      expect(again.session_cart).to eq(product.id.to_s => { 'brand_new' => 2 }, other_product.id.to_s => { 'misb' => 1 })
      expect(again.session_marker['digest']).not_to eq(first.session_marker['digest'])
    end

    it 'does not import a session that moved on after hydration, and loses nothing' do
      first = reconcile(session_cart)
      edited = first.session_cart.deep_dup
      edited[product.id.to_s]['brand_new'] = 3

      again = reconcile(edited, marker: first.session_marker, session_id: renewed_session_id)

      expect(again.status).to eq(:session_ahead)
      expect(again).not_to be_success
      expect(again).not_to be_hydrate
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
    end

    it 'refuses a marker that points at another user cart' do
      first = reconcile(session_cart)
      intruder = create(:user)

      again = reconcile(first.session_cart, user: intruder, marker: first.session_marker, session_id: renewed_session_id)

      expect(again.status).to eq(:foreign_session)
      expect(again).not_to be_hydrate
      expect(intruder.shopping_carts.count).to eq(0)
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
      expect(CartSessionImport.count).to eq(1)
    end

    it 'ignores a malformed marker and behaves like a first authentication' do
      first = reconcile(session_cart)

      again = reconcile(first.session_cart, marker: 'garbage', session_id: session_id)

      expect(again.status).to eq(:reused)
      expect(quantities(first.cart)).to eq([product.id, 'brand_new'] => 2)
    end
  end

  describe 'hydration that would not fit the cookie session' do
    it 'imports and records the marker but leaves the session cart alone, and never re-imports' do
      cart = create(:shopping_cart, user: user)
      products = create_list(:product, 120, skip_seed_inventory: true)
      products.each { |p| create(:shopping_cart_item, shopping_cart: cart, product: p, quantity: 1) }
      session_cart = { product.id.to_s => { 'brand_new' => 1 } }

      result = reconcile(session_cart)

      expect(result.status).to eq(:hydration_too_large)
      expect(result).to be_success
      expect(result).not_to be_hydrate
      expect(result).to be_mark
      expect(result.session_marker).to eq(
        'cart_id' => cart.id, 'digest' => ShoppingCarts::SessionCartNormalizer.call(session_cart).digest
      )
      expect(result.details[:persistent_lines]).to eq(121)
      expect(quantities(cart)[[product.id, 'brand_new']]).to eq(1)
      expect(CartSessionImport.count).to eq(1)

      again = reconcile(session_cart, marker: result.session_marker, session_id: SecureRandom.hex(16))
      expect(again.status).to eq(:hydration_too_large)
      expect(quantities(cart)[[product.id, 'brand_new']]).to eq(1)
      expect(CartSessionImport.count).to eq(1)
    end
  end

  describe 'authority boundaries' do
    it 'never touches inventory, sale orders or pricing' do
      seeded = create(:product)
      before = [Inventory.count, Inventory.pluck(:status, :sale_order_id), SaleOrder.count, SaleOrderItem.count]

      reconcile({ seeded.id.to_s => { 'brand_new' => 2 } })

      expect([Inventory.count, Inventory.pluck(:status, :sale_order_id), SaleOrder.count, SaleOrderItem.count]).to eq(before)
      expect(ShoppingCartItem.column_names).not_to include('price', 'unit_price', 'subtotal', 'discount', 'tax')
    end
  end
end
