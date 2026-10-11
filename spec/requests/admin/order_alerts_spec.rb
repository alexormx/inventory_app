# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin alertas de órdenes', type: :request do
  it 'muestra cada sección con enlace a la orden y no modifica nada' do
    sign_in create(:user, :admin)
    old = create(:sale_order, status: 'Pending').tap { |o| o.update_columns(created_at: 40.days.ago) }

    expect { get admin_order_alerts_path }.not_to(change { SaleOrder.pluck(:id, :status, :updated_at) })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Alertas de órdenes', old.id, admin_sale_order_path(old))
  end

  it 'no deja entrar a un cliente' do
    sign_in create(:user)
    get admin_order_alerts_path
    expect(response).to redirect_to(root_path)
  end

  it 'el dashboard avisa cuando hay órdenes que atender' do
    sign_in create(:user, :admin)
    create(:sale_order, status: 'Pending').tap { |o| o.update_columns(created_at: 40.days.ago) }
    get admin_dashboard_path
    expect(response.body).to include('requieren atención', admin_order_alerts_path)
  end
end
