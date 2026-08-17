# frozen_string_literal: true

require 'rails_helper'

# Una orden cancelada sigue existiendo en el historial del cliente, pero su
# valor ya no es realizable ni cobrable: no debe sumar a ventas ni a adeudo.
# Los agregados de Admin::UsersController sumaban todas las órdenes sin filtrar
# por estado, así que arrastraban el valor de las canceladas.
RSpec.describe 'Admin::Users canceled order financials', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user, role: 'customer', name: 'Cliente Prueba') }

  before { sign_in admin }

  # Se cancela por el flujo canónico allí donde aplica; aquí basta con dejar el
  # registro en su estado final para fijar el comportamiento de los agregados.
  def canceled_order(value)
    create(:sale_order, user: customer, status: 'Pending',
                        subtotal: value, total_order_value: value).tap do |order|
      order.update_column(:status, 'Canceled')
    end
  end

  def live_order(value, status: 'Confirmed')
    create(:sale_order, user: customer, status: 'Pending',
                        subtotal: value, total_order_value: value).tap do |order|
      order.update_column(:status, status)
    end
  end

  describe 'GET /admin/users/:id' do
    it 'excludes canceled orders from total sales and debt' do
      live_order(1000.0)
      canceled_order(750.0)

      get admin_user_path(customer)

      expect(response).to have_http_status(:success)
      expect(controller.instance_variable_get(:@total_sales)).to eq(1000.0)
      expect(controller.instance_variable_get(:@balance_due)).to eq(1000.0)
    end

    it 'keeps canceled orders visible as history' do
      canceled = canceled_order(750.0)
      live_order(1000.0)

      get admin_user_path(customer)

      expect(controller.instance_variable_get(:@sale_count)).to eq(2)
      expect(controller.instance_variable_get(:@canceled_sale_count)).to eq(1)
      expect(controller.instance_variable_get(:@recent_sales)).to include(canceled)
    end

    it 'reports zero sales and zero debt when every order is canceled' do
      canceled_order(500.0)
      canceled_order(250.0)

      get admin_user_path(customer)

      expect(controller.instance_variable_get(:@total_sales)).to eq(0)
      expect(controller.instance_variable_get(:@balance_due)).to eq(0)
      expect(controller.instance_variable_get(:@sale_count)).to eq(2)
    end

    it 'subtracts completed payments from the debt of live orders only' do
      order = live_order(1000.0)
      create(:payment, sale_order: order, amount: 400.0, status: 'Completed')
      canceled_order(900.0)

      get admin_user_path(customer)

      expect(controller.instance_variable_get(:@balance_due)).to eq(600.0)
    end

    it 'never reports a negative debt when an order is overpaid' do
      order = live_order(500.0)
      create(:payment, sale_order: order, amount: 500.0, status: 'Completed')

      get admin_user_path(customer)

      expect(controller.instance_variable_get(:@balance_due)).to eq(0)
    end
  end

  describe 'GET /admin/users (index aggregates)' do
    it 'excludes canceled value from the per-user sales total and debt columns' do
      live_order(1000.0)
      canceled_order(750.0)

      get admin_users_path

      expect(response).to have_http_status(:success)
      row = controller.instance_variable_get(:@users).detect { |u| u.id == customer.id }
      expect(row.sales_total_mxn.to_d).to eq(1000.0)
      expect(row.balance_due_mxn.to_d).to eq(1000.0)
    end
  end

  # Las subconsultas crudas del índice llevan 'Canceled' escrito como literal
  # (el escáner de seguridad no puede verificar una interpolación aunque venga
  # de una constante). Si la constante cambia, hay que actualizar esos literales
  # y esta prueba lo obliga.
  describe 'the raw-SQL literals and the constant' do
    it 'still has Canceled as the only non-active status' do
      expect(SaleOrder::NON_ACTIVE_TOTAL_STATUSES).to eq(['Canceled'])
    end
  end

  describe 'the canonical scope' do
    it 'keeps canceled orders out of active totals but inside the base relation' do
      live_order(1000.0)
      canceled_order(750.0)

      all_orders = SaleOrder.where(user_id: customer.id)
      expect(all_orders.count).to eq(2)
      expect(all_orders.active_for_totals.count).to eq(1)
      expect(all_orders.active_for_totals.sum(:total_order_value)).to eq(1000.0)
    end
  end
end
