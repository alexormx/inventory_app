# frozen_string_literal: true

require 'rails_helper'

# El filtro de periodo del panel sólo cambiaba los números: las etiquetas
# seguían diciendo "YTD", los rankings ignoraban el periodo y la rotación se
# juzgaba con umbrales anuales sobre ventanas de 30 días.
RSpec.describe 'Admin Dashboard period handling', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:target_year) { 2600 + SecureRandom.random_number(200) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def page
    Nokogiri::HTML(response.body)
  end

  def kpi(title)
    page.css('.admin-kpi-card, .admin-kpi-stat').find { |c| c.at_css('.kpi-label').text.include?(title) } ||
      raise("KPI #{title.inspect} no encontrado")
  end

  def sale(date:, price:, cost:, item: product)
    order = create(:sale_order, status: 'Delivered', order_date: date, subtotal: price, tax_rate: 0, total_tax: 0,
                                total_order_value: price)
    create(:sale_order_item, sale_order: order, product: item, quantity: 1, unit_final_price: price,
                             total_line_cost: price, unit_acquisition_cost: cost)
  end

  before { sign_in admin }

  it 'reports the gross margin change against last year in percentage points' do
    travel_to(Time.zone.local(target_year, 6, 15, 12)) do
      sale(date: Date.new(target_year, 3, 1), price: 100, cost: 60)       # 40 %
      sale(date: Date.new(target_year - 1, 3, 1), price: 100, cost: 80)   # 20 %

      get admin_dashboard_path

      expect(kpi('Margen Bruto').at_css('.kpi-delta').text.squish).to eq('vs LY: +20.0 pp')
    end
  end

  it 'labels the period KPIs with the selected period instead of a fixed YTD' do
    get admin_dashboard_path, params: { range: 'last_30' }

    %w[Ingresos Utilidad\ Bruta Margen\ Bruto Flujo\ de\ Caja Órdenes\ Venta].each do |title|
      expect(kpi(title).at_css('.kpi-label').text.squish).to eq("#{title} · Últimos 30 días")
    end
    expect(response.body).not_to include('Comparativa YTD')
  end

  it 'points the first ranking tab at the selected period' do
    get admin_dashboard_path, params: { range: 'custom', start_date: '2026-01-01', end_date: '2026-01-31' }

    frame = page.at_css('turbo-frame#frame-sellers-range')
    expect(frame).to be_present
    expect(Rack::Utils.parse_query(URI(frame['src']).query))
      .to include('period' => 'range', 'range' => 'custom', 'start_date' => '2026-01-01', 'end_date' => '2026-01-31')
  end

  it 'ranks only the sales inside the selected period' do
    travel_to(Time.zone.local(target_year, 6, 15, 12)) do
      january = create(:product, product_name: "Enero #{SecureRandom.hex(3)}", skip_seed_inventory: true)
      may = create(:product, product_name: "Mayo #{SecureRandom.hex(3)}", skip_seed_inventory: true)
      sale(date: Date.new(target_year, 1, 10), price: 100, cost: 50, item: january)
      sale(date: Date.new(target_year, 5, 10), price: 100, cost: 50, item: may)

      get admin_dashboard_sellers_path,
          params: { period: 'range', range: 'custom', start_date: "#{target_year}-01-01", end_date: "#{target_year}-01-31" }

      expect(response.body).to include(january.product_name)
      expect(response.body).not_to include(may.product_name)
    end
  end

  it 'annualizes inventory rotation so short periods are judged on the same scale' do
    travel_to(Time.zone.local(target_year, 6, 15, 12)) do
      sale(date: Date.new(target_year, 6, 1), price: 200, cost: 100)
      product.update_column(:current_inventory_value, 1000)

      get admin_dashboard_path, params: { range: 'last_30' }

      # 100 de costo en 31 días sobre 1 000 de inventario = 0.10 en el periodo,
      # 1.18 al año.
      expect(kpi('Valor Inventario')['title']).to include('Rotación anualizada: 1.18')
    end
  end
end
