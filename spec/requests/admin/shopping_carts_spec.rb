# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin historial de carritos', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:ana) { create(:user, name: 'Ana Compradora', email: 'ana@example.com') }
  let(:beto) { create(:user, name: 'Beto Cliente', email: 'beto@example.com') }
  let(:product) { create(:product, skip_seed_inventory: true, product_name: 'Skyline GT-R', selling_price: 250) }

  def cart(user, status, **attrs)
    create(:shopping_cart, status.to_sym, user: user, **attrs).tap do |c|
      create(:shopping_cart_item, shopping_cart: c, product: product, product_reference: product.id, quantity: 2)
    end
  end

  let!(:active)    { cart(ana, :owned, last_activity_at: 1.hour.ago) }
  let!(:converted) { cart(beto, :converted) }
  let!(:expired)   { cart(beto, :expired, checkout_notes: 'Entregar en la tarde') }

  before { sign_in admin }

  it 'lista los carritos activos con cuánto falta para vencer, y cuenta cada estado' do
    get admin_shopping_carts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Activos (1)', 'Convertidos en orden (1)', 'Vencidos (1)')
    expect(response.body).to include(admin_shopping_cart_path(active), 'Ana Compradora', 'vence en')
    expect(response.body).not_to include(admin_shopping_cart_path(expired))
  end

  it 'muestra los convertidos con enlace a su orden' do
    get admin_shopping_carts_path(status: 'converted')
    expect(response.body).to include(admin_sale_order_path(converted.sale_order_id))
  end

  it 'muestra los vencidos' do
    get admin_shopping_carts_path(status: 'expired')
    expect(response.body).to include(admin_shopping_cart_path(expired))
    expect(response.body).not_to include(admin_shopping_cart_path(active))
  end

  it 'busca por correo o nombre del cliente' do
    get admin_shopping_carts_path(status: 'all', q: 'beto@')
    expect(response.body).to include(admin_shopping_cart_path(converted), admin_shopping_cart_path(expired))
    expect(response.body).not_to include(admin_shopping_cart_path(active))
  end

  it 'el detalle muestra productos, valor, notas y línea de tiempo, sin modificar nada' do
    expect { get admin_shopping_cart_path(expired) }.not_to(change { ShoppingCart.pluck(:id, :status, :updated_at) })
    expect(response.body).to include('Skyline GT-R', 'Vencido', 'Entregar en la tarde', '$500')
  end

  it 'no deja entrar a un cliente' do
    sign_in ana
    get admin_shopping_carts_path
    expect(response).to redirect_to(root_path)
  end
end
