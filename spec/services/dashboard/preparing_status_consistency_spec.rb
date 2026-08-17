# frozen_string_literal: true

require 'rails_helper'

# Qué cuenta como venta activa lo define Dashboard::Metrics::SALE_STATUSES.
# KpiCalculator, ChartDataBuilder y TopRankingsBuilder llevaban la lista escrita
# a mano y omitían 'Preparing', un estado posterior a Confirmed: esas órdenes
# ya están confirmadas y surtiéndose, pero desaparecían de KPIs, gráficas y
# rankings mientras sí aparecían en el resto del panel.
RSpec.describe 'Dashboard active sale statuses', type: :service do
  it 'treats Preparing as an active sale in the canonical constant' do
    expect(Dashboard::Metrics::SALE_STATUSES).to include('Preparing')
  end

  # Fija la invariante: ningún servicio del panel puede volver a llevar su
  # propia lista de estados activos.
  it 'has no dashboard service carrying its own hardcoded status list' do
    offenders = Dir[Rails.root.join('app/services/dashboard/*.rb')].select do |path|
      source = File.read(path)
      source.match?(/status:\s*\[\s*['"]Confirmed['"]/) ||
        source.match?(/status:\s*%w\[\s*Confirmed/)
    end

    expect(offenders).to be_empty,
                         "Estos servicios definen su propia lista en vez de usar " \
                         "Dashboard::Metrics::SALE_STATUSES: #{offenders.map { |p| File.basename(p) }.join(', ')}"
  end

  describe 'services that build their scope from the constant' do
    let(:customer) { create(:user) }

    def order_with_status(status, value)
      create(:sale_order, user: customer, status: 'Pending',
                          subtotal: value, total_order_value: value).tap do |order|
        order.update_column(:status, status)
      end
    end

    it 'includes a Preparing order in the KPI revenue scope' do
      order_with_status('Preparing', 500.0)
      order_with_status('Confirmed', 300.0)
      order_with_status('Canceled', 900.0)

      scope = SaleOrder.where(status: Dashboard::Metrics::SALE_STATUSES)

      expect(scope.count).to eq(2)
      expect(scope.sum(:total_order_value)).to eq(800.0)
    end

    it 'keeps Canceled and Pending out of the active scope' do
      order_with_status('Pending', 100.0)
      order_with_status('Canceled', 100.0)

      expect(SaleOrder.where(status: Dashboard::Metrics::SALE_STATUSES).count).to eq(0)
    end
  end
end
