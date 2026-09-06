# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin user details', type: :request do
  include ActionView::Helpers::NumberHelper

  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user, name: 'Cliente de prueba') }

  def capture_admin_user_show_queries(&block)
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s.squish
      next if payload[:cached]
      next if %w[SCHEMA CACHE].include?(payload[:name])
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  describe 'GET /admin/users/:id' do
    it 'renders the user detail page for an administrator' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(customer.name)
      expect(response.body).to include(customer.email)
    end

    it 'returns not found for a missing user' do
      sign_in admin

      get admin_user_path(id: 0)

      expect(response).to have_http_status(:not_found)
    end

    it 'redirects a non-admin user to the root page' do
      sign_in customer

      get admin_user_path(admin)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('Acceso denegado')
    end

    it 'redirects an unauthenticated user to sign in' do
      get admin_user_path(customer)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'renders a customer with a saved default shipping address' do
      address = create(:shipping_address, user: customer, full_name: 'Ana Destinataria',
                                          line1: 'Calle Roble 123', line2: 'Interior 4')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(address.full_name, address.line1)
    end

    it 'orders multiple addresses with the default first and renders both' do
      secondary = create(:shipping_address, user: customer, full_name: 'Segundo Destino', default: false,
                                            state: nil)
      primary = create(:shipping_address, user: customer, full_name: 'Destino Principal', default: true)
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(primary.full_name, secondary.full_name)
      addresses_card = document.css('h5').find { |h| h.text.include?('Direcciones de Envío') }.ancestors('.card').first
      expect(addresses_card.css('.badge').map(&:text)).to eq(['Principal'])
    end

    it 'renders a customer with no saved shipping addresses' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
    end

    it 'shows the empty orders placeholder for a customer with no orders' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Sin órdenes aún')
    end

    it 'renders unpaid, partially paid and fully paid sale orders with the correct amounts' do
      unpaid = create(:sale_order, user: customer, total_order_value: 100)
      partial = create(:sale_order, user: customer, total_order_value: 200)
      create(:payment, sale_order: partial, amount: 80, status: 'Completed')
      paid = create(:sale_order, user: customer, total_order_value: 150)
      create(:payment, sale_order: paid, amount: 150, status: 'Completed')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      rows = document.css('table tbody tr').index_by { |row| row.at_css('td:first-child').text.strip }

      expect(rows["##{unpaid.id}"].at_css('td:last-child').text).to include('$0')
      expect(rows["##{partial.id}"].at_css('td:last-child').text).to include('$80')
      expect(rows["##{paid.id}"].at_css('td:last-child').text).to include('$150')
    end

    it 'does not run a separate payments query per recent sale order' do
      create_list(:sale_order, 3, user: customer).each do |order|
        create(:payment, sale_order: order, amount: 10, status: 'Completed')
      end
      sign_in admin

      queries = capture_admin_user_show_queries { get admin_user_path(customer) }
      # 2 is the fixed cost of the Customer 360 payments section's own bounded
      # query (an any?/each pair against @recent_payments) - it does not scale
      # with the number of sale orders, unlike the per-order N+1 this guards against.
      payments_queries = queries.select { |sql| sql.match?(/FROM "payments"/) }

      expect(payments_queries.size).to be <= 2
    end

    it 'renders a supplier with recent purchases and total compras' do
      supplier = create(:user, :supplier, name: 'Proveedor de prueba')
      purchase = create(:purchase_order, user: supplier, total_cost_mxn: 500)
      sign_in admin

      get admin_user_path(supplier)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_purchase_order_path(purchase))
      expect(response.body).to include('Total Compras')
    end

    it 'renders discount, offline-created badge and notes for a customer' do
      customer.update!(discount_rate: 15, created_offline: true, notes: 'Cliente VIP de tienda física')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('15%', 'Cliente VIP de tienda física')
    end

    it 'redirects a supplier from the admin route like any other non-admin' do
      supplier = create(:user, :supplier)
      sign_in supplier

      get admin_user_path(customer)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('Acceso denegado')
    end
  end

  describe 'Customer 360 overview' do
    it 'shows the delivered order count' do
      create(:sale_order, user: customer, status: 'Delivered')
      create(:sale_order, user: customer, status: 'Pending')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Órdenes Entregadas')
      document = Nokogiri::HTML(response.body)
      metric = document.css('.text-muted').find { |el| el.text.strip == 'Órdenes Entregadas' }.parent
      expect(metric.text).to include('1')
    end
  end

  describe 'Customer 360 orders fulfillment status' do
    it "shows each recent order's shipment status, or none when unshipped" do
      shipped_order = create(:sale_order, user: customer, total_order_value: 100)
      create(:shipment, sale_order: shipped_order, status: :shipped, carrier: 'DHL')
      unshipped_order = create(:sale_order, user: customer, total_order_value: 50)
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      rows = document.css('table').first.css('tbody tr').index_by { |row| row.at_css('td:first-child').text.strip }

      expect(rows["##{shipped_order.id}"].text).to include('Shipped')
      expect(rows["##{unshipped_order.id}"].text).to include('—')
    end

    it 'uses the correct badge color for a Delivered order status' do
      order = create(:sale_order, user: customer, status: 'Delivered', total_order_value: 100)
      create(:payment, sale_order: order, amount: 100, status: 'Completed')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      row = document.css('table').first.css('tbody tr').find { |r| r.text.include?("##{order.id}") }
      expect(row.at_css('.badge')['class']).to include('bg-success')
    end
  end

  describe 'Customer 360 payments' do
    it 'renders recent payments with order link, method, amount and status' do
      order = create(:sale_order, user: customer, total_order_value: 200)
      completed = create(:payment, sale_order: order, amount: 120, payment_method: 'efectivo', status: 'Completed')
      pending = create(:payment, sale_order: order, amount: 80, payment_method: 'transferencia_bancaria',
                                 status: 'Pending')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_sale_order_path(order))
      expect(response.body).to include('Efectivo', 'Transferencia bancaria', 'Completed', 'Pending')
      expect(response.body).to include(number_to_currency(completed.amount, unit: '$', precision: 0))
      expect(response.body).to include(number_to_currency(pending.amount, unit: '$', precision: 0))
    end

    it 'shows the empty state when the customer has no payments' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Sin pagos registrados')
    end

    it 'does not run a separate sale_order query per recent payment' do
      create_list(:sale_order, 3, user: customer).each do |order|
        create(:payment, sale_order: order, amount: 10, status: 'Completed')
      end
      sign_in admin

      queries = capture_admin_user_show_queries { get admin_user_path(customer) }
      # The N+1 signature is a separate single-record lookup per association
      # access (`... WHERE "sale_orders"."id" = $1`); a correct `includes`
      # preload issues one batched `IN (...)` query instead. Matching on the
      # singular form (not `sale_order_id`, which appears in unrelated
      # subqueries) proves no per-row query was introduced.
      per_row_sale_order_queries = queries.select { |sql| sql.match?(/FROM "sale_orders" WHERE "sale_orders"\."id" = /) }

      expect(per_row_sale_order_queries).to be_empty
    end
  end

  describe 'Customer 360 shipments' do
    it 'renders recent shipments with carrier, tracking, status and order link' do
      order = create(:sale_order, user: customer, total_order_value: 100)
      shipment = create(:shipment, sale_order: order, carrier: 'FedEx', tracking_number: 'TRACK-1',
                                    status: :delivered, estimated_delivery: Date.new(2026, 1, 10),
                                    actual_delivery: Date.new(2026, 1, 12))
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_sale_order_path(order))
      expect(response.body).to include(shipment.carrier, shipment.tracking_number, 'Delivered')
    end

    it 'shows the empty state when the customer has no shipments' do
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Sin envíos registrados')
    end

    it 'does not run a separate sale_order query per recent shipment' do
      create_list(:sale_order, 3, user: customer).each do |order|
        create(:shipment, sale_order: order)
      end
      sign_in admin

      queries = capture_admin_user_show_queries { get admin_user_path(customer) }
      # The N+1 signature is a separate single-record lookup per association
      # access (`... WHERE "sale_orders"."id" = $1`); a correct `includes`
      # preload issues one batched `IN (...)` query instead. Matching on the
      # singular form (not `sale_order_id`, which appears in unrelated
      # subqueries) proves no per-row query was introduced.
      per_row_sale_order_queries = queries.select { |sql| sql.match?(/FROM "sale_orders" WHERE "sale_orders"\."id" = /) }

      expect(per_row_sale_order_queries).to be_empty
    end
  end

  describe 'Customer 360 cross-customer isolation' do
    it "never shows customer B's orders, payments, shipments or addresses on customer A's page" do
      other = create(:user, name: 'Cliente B Privado')
      other_order = create(:sale_order, user: other, total_order_value: 999)
      create(:payment, sale_order: other_order, amount: 999, status: 'Completed')
      create(:shipment, sale_order: other_order, carrier: 'PRIVATE-CARRIER', tracking_number: 'PRIVATE-TRACK')
      create(:shipping_address, user: other, full_name: 'PRIVATE-RECIPIENT')
      sign_in admin

      get admin_user_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other.name, other_order.id, 'PRIVATE-CARRIER', 'PRIVATE-TRACK',
                                            'PRIVATE-RECIPIENT', '999')
    end
  end
end
