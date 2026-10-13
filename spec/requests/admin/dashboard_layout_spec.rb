# frozen_string_literal: true

require 'rails_helper'

# Auditoría del panel (2026-10-12): la comparativa vs año anterior repetía los
# deltas de las tarjetas, la mini-gráfica sólo existía en Ingresos y la página
# mostraba de entrada cifras históricas y gráficas de consulta ocasional.
RSpec.describe 'Admin Dashboard layout', type: :request do
  let(:admin) { create(:user, :admin) }

  def page
    Nokogiri::HTML(response.body)
  end

  def kpi(title)
    page.css('.admin-kpi-card, .admin-kpi-stat').find { |c| c.at_css('.kpi-label').text.include?(title) } ||
      raise("KPI #{title.inspect} no encontrado")
  end

  def collapsed?(node)
    node.ancestors.any? { |a| a['class'].to_s.split.include?('collapse') && !a['class'].to_s.split.include?('show') }
  end

  before do
    sign_in admin
    get admin_dashboard_path
  end

  it 'drops the comparison section that repeated the KPI card deltas' do
    expect(response.body).not_to include('Comparativa vs mismo periodo')
  end

  it 'gives every primary KPI card a 12-month sparkline' do
    ['Ingresos', 'Utilidad Bruta', 'Margen Bruto', 'Flujo de Caja'].each do |title|
      spark = kpi(title).at_css('.kpi-sparkline')
      expect(spark).to be_present, "#{title} sin mini-gráfica"
      expect(JSON.parse(spark['data-chart-data']).size).to eq(12)
      expect(spark['title']).to eq('Últimos 12 meses')
    end
  end

  it 'folds the all-time totals and balances away by default' do
    ['Inversión Total', 'Ventas Históricas', 'Balance Mes Actual', 'Balance Año Actual', 'Balance Histórico'].each do |title|
      expect(collapsed?(kpi(title))).to be(true), "#{title} visible de entrada"
    end
    expect(collapsed?(kpi('Clientes Recurrentes'))).to be(false)
  end

  it 'folds the occasional analytic charts away by default' do
    ['Ventas Mensuales por Categoría', 'Rentabilidad por Marca', 'Rentabilidad por Categoría'].each do |header|
      node = page.css('.card-header span').find { |s| s.text.include?(header) }
      expect(collapsed?(node)).to be(true), "#{header} visible de entrada"
    end
  end
end
