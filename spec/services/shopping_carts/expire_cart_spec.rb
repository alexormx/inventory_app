# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ExpireCart do
  let(:location) { create(:inventory_location) }
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def available_unit
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(status: Inventory.statuses['available'],
                             item_condition: Inventory.item_conditions['brand_new'],
                             inventory_location_id: location.id)
    inventory
  end

  def cart_with_line(idle_for:)
    available_unit
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new')
    cart = ShoppingCarts::ActiveCartResolver.find(user)
    cart.update_columns(last_activity_at: idle_for.ago)
    cart
  end

  it 'considera vencido un carrito activo con líneas y más de 4 h sin cambios' do
    expect(described_class.stale?(cart_with_line(idle_for: 5.hours))).to be(true)
  end

  it 'no considera vencido un carrito con actividad reciente' do
    expect(described_class.stale?(cart_with_line(idle_for: 3.hours))).to be(false)
  end

  it 'no considera vencido un carrito vacío' do
    cart = ShoppingCarts::ActiveCartResolver.find_or_create!(user)
    cart.update_columns(last_activity_at: 5.hours.ago)
    expect(described_class.stale?(cart)).to be(false)
  end

  it 'lo marca vencido, conserva sus líneas y libera sus apartados' do
    cart = cart_with_line(idle_for: 5.hours)
    expect(CartInventoryHold.for_cart(cart).count).to eq(1)

    expect(described_class.call(cart)).to be(true)
    cart.reload
    expect(cart.status).to eq('expired')
    expect(cart.closed_at).to be_present
    expect(cart.shopping_cart_items.count).to eq(1)
    expect(CartInventoryHold.for_cart(cart).count).to eq(0)
    expect(ShoppingCarts::ActiveCartResolver.find(user)).to be_nil
  end

  it 'no lo vence si recibió actividad antes de tomar el candado' do
    cart = cart_with_line(idle_for: 5.hours)
    stale_copy = ShoppingCart.find(cart.id)
    cart.update_columns(last_activity_at: Time.current) # otra pestaña lo tocó
    expect(described_class.call(stale_copy)).to be(false)
    expect(cart.reload.status).to eq('active')
  end

  it 'permite el estado expired sólo con closed_at (restricción de la base)' do
    cart = create(:shopping_cart, :owned)
    # Savepoint: la violación aborta sólo esta subtransacción, no la del spec.
    expect { ShoppingCart.transaction(requires_new: true) { cart.update_columns(status: 'expired') } }
      .to raise_error(ActiveRecord::StatementInvalid, /lifecycle_invariants/)
    expect { cart.update_columns(status: 'expired', closed_at: Time.current) }.not_to raise_error
  end
end
