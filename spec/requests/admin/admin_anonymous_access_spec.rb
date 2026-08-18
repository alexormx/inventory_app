# frozen_string_literal: true

require 'rails_helper'

# Un visitante anónimo en una ruta de admin debe ir al login, no reventar.
# authorize_admin! hace current_user.admin?, así que sin authenticate_user!
# delante current_user es nil y sale un 500 (NoMethodError) en vez del redirect.
RSpec.describe 'Admin routes reject anonymous visitors safely', type: :request do
  # Una ruta GET representativa por cada controlador que le faltaba el guard.
  {
    'collectibles' => '/admin/collectibles',
    'inventory_audits' => '/admin/inventory_audit',
    'inventory_events' => '/admin/inventory_events',
    'preorders_audits' => '/admin/preorders_audit',
    'sale_orders_audits' => '/admin/sale_orders_audit'
  }.each do |name, path|
    it "redirects anonymous users away from #{name} instead of raising" do
      get path

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  it 'still lets an admin through' do
    sign_in create(:user, :admin)

    get '/admin/collectibles'

    expect(response).to have_http_status(:success)
  end

  it 'still denies a signed-in non-admin' do
    sign_in create(:user, role: :customer)

    get '/admin/collectibles'

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include('Acceso denegado')
  end
end
