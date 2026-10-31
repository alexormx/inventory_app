# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::AnonymizeAccount do
  let(:user) do
    create(:user, name: 'Ana Cliente', phone: '5512345678', address: 'Calle Roble 123',
                  tax_id: 'XAXX010101000', notes: 'nota', api_token: 'tok-123')
  end

  it 'borra los datos personales y conserva los pedidos' do
    order = create(:sale_order, user: user)
    create(:shipping_address, user: user)
    Favorite.save_for(user, create(:product))
    NewsletterSubscriber.create!(email: user.email, subscribed_at: Time.current)
    old_email = user.email

    described_class.call(user)
    user.reload

    expect(user.name).to eq('Cliente eliminado')
    expect(user.email).to end_with("@#{User::ANONYMIZED_EMAIL_DOMAIN}")
    expect([user.phone, user.address, user.tax_id, user.notes, user.api_token]).to all(be_nil)
    expect(user).to be_anonymized
    expect(user.valid_password?('password')).to be(false)
    expect(user.shipping_addresses).to be_empty
    expect(user.favorites).to be_empty
    expect(NewsletterSubscriber.where(email: old_email)).not_to exist
    expect(order.reload.user_id).to eq(user.id)
  end

  it 'cierra el carrito activo y libera sus apartados' do
    cart = create(:shopping_cart, user: user)

    described_class.call(user)

    expect(cart.reload.status).to eq('cleared')
    expect(cart.closed_at).to be_present
    expect(CartInventoryHold.for_cart(cart)).not_to exist
  end

  it 'impide volver a iniciar sesión' do
    described_class.call(user)

    expect(user.reload.active_for_authentication?).to be(false)
  end

  it 'no anonimiza a un administrador' do
    admin = create(:user, role: 'admin')

    expect { described_class.call(admin) }.to raise_error(described_class::NotAllowed)
    expect(admin.reload).not_to be_anonymized
  end
end
