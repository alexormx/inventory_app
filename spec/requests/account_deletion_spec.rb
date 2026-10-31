# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Eliminar mi cuenta', type: :request do
  it 'anonimiza al cliente con pedidos y cierra su sesión' do
    user = create(:user, name: 'Ana Cliente')
    order = create(:sale_order, user: user)
    sign_in user

    delete user_registration_path

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include('Tu cuenta ha sido eliminada')
    expect(user.reload).to be_anonymized
    expect(order.reload.user_id).to eq(user.id)
    get profile_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
