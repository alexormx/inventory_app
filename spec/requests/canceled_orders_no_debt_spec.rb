# frozen_string_literal: true

require 'rails_helper'

# Una orden cancelada no se cobra: su total queda registrado y sin pagos que lo
# compensen, pero no es adeudo. El modelo ya lo sabía (open_receivables); la
# lista, el detalle, la ficha del cliente y el resumen del pedido calculaban
# "total - pagado" por su cuenta y la mostraban como deuda.
RSpec.describe 'Canceled and returned orders carry no debt', type: :request do
  %w[Canceled Returned].each do |closed_status|
  context "when the order is #{closed_status}" do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user, password: 'password123', password_confirmation: 'password123') }
  let!(:canceled) { create(:sale_order, user: customer, status: closed_status, total_order_value: 500, subtotal: 500, tax_rate: 0, total_tax: 0) }
  let!(:owed) { create(:sale_order, user: customer, status: 'Delivered', total_order_value: 200, subtotal: 200, tax_rate: 0, total_tax: 0) }

  def page
    Nokogiri::HTML(response.body)
  end

  def row_for(record)
    key = record.is_a?(User) ? record.email : record.id.to_s
    page.css('tbody tr').find { |tr| tr.to_html.include?(key) }
  end

  describe 'admin sale orders list' do
    before { sign_in admin }

    it 'leaves canceled orders out of the total debt' do
      get admin_sale_orders_path(user_id: customer.id)

      card = page.css('.card-body').find { |c| c.text.include?('Adeudo Total') }
      expect(card.text.squish).to include('$200', '1 con saldo')
      debt_cell = row_for(canceled).css('td.text-end').find { |td| td.at_css('.badge') }
      expect(debt_cell.text.squish).to eq('Sin adeudo')
    end

    it 'does not list canceled orders under the debt filter' do
      get admin_sale_orders_path(user_id: customer.id, due: 1)

      expect(row_for(owed)).to be_present
      expect(row_for(canceled)).to be_nil
    end
  end

  it 'shows no debt on the admin detail of a canceled order' do
    sign_in admin

    get admin_sale_order_path(canceled)

    debt = page.css('.small.text-muted').find { |d| d.text.strip == 'Adeudo' }.next_element
    expect(debt.text.squish).not_to include('$500')
    expect(response.body).not_to include('Pagada')
  end

  it 'does not flag a canceled order as pending on the customer page' do
    sign_in admin

    get admin_user_path(customer)

    expect(response.body).not_to include('Pendiente: $500')
  end

  it 'counts only the collectible orders in the customer debt' do
    sign_in admin

    get admin_user_path(customer)
    stat = page.css('.card-body').find { |c| c.text.include?('Adeudo Pendiente') }
    expect(stat.text.squish).to include('$200')

    get admin_users_path
    expect(row_for(customer).css('td.text-end span.text-danger').map { |d| d.text.strip }).to eq(['$200'])
  end

  it 'does not ask the customer to pay a canceled order' do
    sign_in customer

    get summary_order_path(canceled)

    remaining = page.css('dt').find { |dt| dt.text.include?('Resta por pagar') }.next_element
    expect(remaining.text.squish).to eq(closed_status == 'Canceled' ? 'Orden cancelada' : 'Orden devuelta')
  end
  end
  end
end
