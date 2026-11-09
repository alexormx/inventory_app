# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Finanzas', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  # Año futuro fijo: con un travel_to al pasado el recargador de clases (enable_reloading en test)
  # ve los archivos recién editados como "del futuro" y recarga constantes a media suite.
  around { |example| travel_to(Time.zone.local(2600, 6, 15, 12)) { example.run } }

  def page
    Nokogiri::HTML(response.body)
  end

  def concluded_sale(price:, cost:, on:)
    order = create(:sale_order)
    order.update_columns(total_order_value: price, status: 'Delivered', order_date: on)
    item = create(:sale_order_item, sale_order: order, product: product, quantity: 1, unit_cost: price,
                                    unit_final_price: price, total_line_cost: price)
    item.update_columns(total_line_cost: price, unit_acquisition_cost: cost)
    order.update_columns(total_order_value: price)
    payment = create(:payment, sale_order: order, amount: price)
    payment.update_columns(paid_at: on, status: 'Completed')
    order
  end

  context 'como administrador' do
    before { sign_in admin }

    it 'muestra la tabla del año con las filas de utilidad, flujo y saldos' do
      get admin_finances_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Utilidad del mes', 'Flujo del mes', 'Anticipos por entregar', 'en curso')
      expect(response.body).to include('Finanzas cuenta cada venta en el mes en que el cliente termina de pagar; ' \
                                       'el Panel de control la cuenta en la fecha de la orden, ' \
                                       'por eso sus cifras pueden diferir.')
    end

    it 'muestra la utilidad de la venta en el mes de conclusión' do
      concluded_sale(price: 100, cost: 60, on: Date.new(2600, 3, 10))

      get admin_finances_path

      headers = page.css('thead th').map { |th| th.text.squish }
      march = headers.index { |h| h.start_with?('Mar') }
      row = page.css('tbody tr').find { |tr| tr.at_css('th')&.text&.include?('Utilidad del mes') }
      expect(row.css('td')[march - 1].text).to include('40')
    end

    it 'vista histórica muestra columnas por año' do
      get admin_finances_path(view: 'history')

      expect(response).to have_http_status(:ok)
      expect(page.css('thead th').map { |th| th.text.squish }).to include(a_string_starting_with('2600'))
      expect(response.body).to include('Utilidad del año', 'Por meses')
    end

    it 'acota años inválidos sin error' do
      ['abc', '1900', '3000', ''].each do |value|
        get admin_finances_path(year: value)

        expect(response).to have_http_status(:ok)
        expect(page.at_css('h1').text).to include('2600')
      end
    end

    it 'descarga CSV' do
      get admin_finances_path(format: :csv)

      expect(response.media_type).to eq('text/csv')
      expect(response.body).to start_with("﻿")
      expect(response.headers['Content-Disposition']).to include('finanzas-2600-2600-06-15.csv')
    end

    it 'el menú lateral enlaza a Finanzas' do
      get admin_dashboard_path

      expect(page.css('a').map { |a| a['href'] }).to include(admin_finances_path)
    end
  end

  it 'redirige a no administradores' do
    sign_in create(:user)

    get admin_finances_path

    expect(response).to redirect_to(root_path)
  end
end
