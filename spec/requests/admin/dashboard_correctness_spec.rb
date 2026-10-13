# frozen_string_literal: true

require 'rails_helper'

# Defectos detectados en la auditoría del panel (2026-10-12): cifras que no
# cuadraban entre sí, una tarjeta que nunca mostraba nada y tooltips cortados.
RSpec.describe 'Admin Dashboard correctness', type: :request do
  let(:admin) { create(:user, :admin) }
  # Año aislado: las demás pruebas crean órdenes en el año en curso.
  let(:target_year) { 2400 + SecureRandom.random_number(200) }

  def page
    Nokogiri::HTML(response.body)
  end

  def kpi(title)
    card = page.css('.admin-kpi-card, .admin-kpi-stat').find { |c| c.at_css('.kpi-label').text.include?(title) }
    raise "KPI #{title.inspect} no encontrado" unless card

    card
  end

  def kpi_value(title)
    kpi(title).at_css('.kpi-value').children.first.text.strip
  end

  def sale_order(status:, date:, value: 100)
    create(:sale_order, status: status, order_date: date, subtotal: value, tax_rate: 0, total_tax: 0, total_order_value: value)
  end

  def purchase_order(status:, date:, cost:)
    create(:purchase_order, status: status, order_date: date, total_order_cost: cost, total_cost_mxn: cost, subtotal: cost,
                            expected_delivery_date: date + 5.days)
  end

  before { sign_in admin }

  it 'renders every KPI tooltip as a complete, quoted title attribute' do
    get admin_dashboard_path

    expect(kpi('Utilidad Bruta')['title']).to eq('Ganancia = Ventas - COGS.')
    expect(kpi('Ticket Promedio')['title']).to eq('Valor promedio por orden de venta.')
  end

  it 'computes the cash flow KPI with income and purchases from the same selected period' do
    travel_to(Time.zone.local(target_year, 6, 15, 12)) do
      early = sale_order(status: 'Delivered', date: Date.new(target_year, 1, 5))
      recent = sale_order(status: 'Delivered', date: Date.new(target_year, 5, 25))
      create(:payment, sale_order: early, amount: 1000, payment_method: 'efectivo', status: 'Completed', paid_at: Date.new(target_year, 1, 10))
      create(:payment, sale_order: recent, amount: 100, payment_method: 'efectivo', status: 'Completed', paid_at: Date.new(target_year, 5, 25))
      purchase_order(status: 'Delivered', date: Date.new(target_year, 5, 25), cost: 30)

      get admin_dashboard_path, params: { range: 'last_30' }

      # Antes: cobros desde el 1 de enero (1 100) menos compras de 30 días (30).
      expect(kpi_value('Flujo de Caja')).to eq('$ 70.00')
    end
  end

  it 'counts only confirmed-or-later orders as sales in the headline KPIs' do
    travel_to(Time.zone.local(target_year, 6, 15, 12)) do
      product = create(:product, skip_seed_inventory: true)
      { 'Confirmed' => 100, 'Pending' => 500, 'Returned' => 300 }.each do |status, price|
        order = sale_order(status: status, date: Date.new(target_year, 3, 1), value: price)
        create(:sale_order_item, sale_order: order, product: product, quantity: 1,
                                 unit_final_price: price, unit_cost: 10, total_line_cost: price)
      end

      get admin_dashboard_path

      expect(kpi_value('Ingresos')).to eq('$ 100.00')
      expect(kpi_value('Órdenes Venta')).to eq('1')
    end
  end

  it 'shows the most recently delivered purchase order as the last received purchase' do
    delivered = purchase_order(status: 'Delivered', date: Date.current, cost: 50)

    get admin_dashboard_path

    activity = page.css('.admin-activity-card div').find { |d| d.text.include?('Última compra recibida') }
    expect(activity.at_css('a')&.text).to eq(delivered.id.to_s)
  end

  it 'gives every real sale and purchase order status its own donut color' do
    SaleOrder::STATUSES.each { |status| sale_order(status: status, date: Date.current) }
    %w[Pending In\ Transit Delivered Canceled].each { |status| purchase_order(status: status, date: Date.current, cost: 10) }

    get admin_dashboard_path, params: { exclude_canceled: '0' }

    series = page.css('[data-chart-type="pie"]').flat_map { |chart| JSON.parse(chart['data-chart-series']) }
    uncolored = series.select { |slice| slice.dig('itemStyle', 'color') == '#64748b' }.map { |slice| slice['name'] }
    expect(series.map { |slice| slice['name'] }).to include('Pending', 'In Transit', 'Returned', 'Delivered')
    expect(uncolored).to be_empty
  end

  # La vista carga los rankings por frames; el index llegó a calcularlos
  # también y nunca los mostraba (140 consultas por visita en un dyno de 512 MB).
  it 'does not compute rankings that the page loads through frames' do
    get admin_dashboard_path
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get admin_dashboard_path }

    expect(queries).to be <= 100
  end

  it 'defers every ranking frame until its tab is actually shown' do
    get admin_dashboard_path

    frames = page.css('turbo-frame[src]')
    expect(frames).not_to be_empty
    expect(frames.reject { |frame| frame['loading'] == 'lazy' }.map { |frame| frame['id'] }).to be_empty
  end
end
