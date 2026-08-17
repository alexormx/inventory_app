# frozen_string_literal: true

require 'rails_helper'

# Las estadísticas de venta de un producto son un derivado de sus líneas, pero
# lo que decide si una línea cuenta es el ESTADO de su orden. Hasta ahora sólo
# se recalculaban cuando cambiaba la línea, así que una orden que pasaba de
# Pending a Confirmed dejaba las cifras del producto congeladas.
#
# Regla canónica fijada aquí: una venta cuenta cuando la orden está en
# SaleOrder::ACTIVE_SALE_STATUSES (Confirmed, Preparing, In Transit, Delivered).
# Pending no cuenta: es una orden todavía no confirmada como venta. Canceled
# tampoco.
RSpec.describe 'Product sales stats stay in sync with sale order status', type: :model do
  let(:customer) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true, selling_price: 20.0, minimum_price: 1.0) }

  # Pago parcial: satisface "debe existir un pago" para poder transicionar, sin
  # cubrir el total (que promovería la orden automáticamente).
  def order_ready_for_transitions(quantity: 3, status: 'Pending')
    order = create(:sale_order, user: customer, status: status,
                                subtotal: 100.0, total_order_value: 100.0)
    create(:sale_order_item, sale_order: order, product: product,
                             quantity: quantity, unit_cost: 20.0, unit_final_price: 20.0)
    create(:payment, sale_order: order, amount: 1.0, status: 'Pending')
    create(:shipment, sale_order: order)
    order.reload
  end

  def units_sold
    product.reload.total_units_sold
  end

  describe 'CASE A — Pending is not a sale' do
    it 'does not count a Pending order toward units sold' do
      order_ready_for_transitions(quantity: 3)

      expect(units_sold).to eq(0)
      expect(product.total_sales_quantity).to eq(0)
      expect(product.total_sales_value).to eq(0)
    end
  end

  describe 'CASE B — Pending -> Confirmed refreshes without touching the line' do
    it 'counts the units once the order is confirmed' do
      order = order_ready_for_transitions(quantity: 3)
      expect(units_sold).to eq(0)

      order.update!(status: 'Confirmed')

      expect(units_sold).to eq(3)
      expect(product.total_sales_quantity).to eq(3)
      expect(product.total_sales_value).to eq(60.0)
    end
  end

  describe 'CASE C/D/E — moving through the active statuses keeps the sale counted' do
    it 'holds the units across Confirmed -> Preparing -> In Transit -> Delivered' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')
      expect(units_sold).to eq(3)

      order.update!(status: 'Preparing')
      expect(units_sold).to eq(3)

      order.update!(status: 'In Transit')
      expect(units_sold).to eq(3)

      order.update!(status: 'Delivered')
      expect(units_sold).to eq(3)
    end

    it 'drops the units again if the order degrades back to Pending' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')
      expect(units_sold).to eq(3)

      order.update!(status: 'Pending')

      expect(units_sold).to eq(0)
    end
  end

  describe 'CASE F — cancellation' do
    # Tras el guard de cancelación, el servicio canónico sólo acepta órdenes
    # Pending, y Pending ya no cuenta como venta: cancelar no puede alterar las
    # estadísticas porque la orden nunca aportó nada.
    it 'leaves stats at zero when a Pending order is canceled through the canonical service' do
      order = order_ready_for_transitions(quantity: 3)
      expect(units_sold).to eq(0)

      SaleOrders::CancelOrderService.new(order).call

      expect(order.reload.status).to eq('Canceled')
      expect(units_sold).to eq(0)
    end

    it 'does not count a record imported as already Canceled' do
      canceled = create(:sale_order, user: customer, status: 'Canceled',
                                     subtotal: 100.0, total_order_value: 100.0)
      create(:sale_order_item, sale_order: canceled, product: product,
                               quantity: 4, unit_cost: 20.0, unit_final_price: 20.0)

      expect(units_sold).to eq(0)
    end
  end

  describe 'CASE G — mixed statuses on the same product' do
    it 'counts only Confirmed + Preparing + Delivered' do
      pending_order = order_ready_for_transitions(quantity: 2)

      confirmed = order_ready_for_transitions(quantity: 3)
      confirmed.update!(status: 'Confirmed')

      preparing = order_ready_for_transitions(quantity: 4)
      preparing.update!(status: 'Confirmed')
      preparing.update!(status: 'Preparing')

      delivered = order_ready_for_transitions(quantity: 5)
      delivered.update!(status: 'Confirmed')
      delivered.update!(status: 'Delivered')

      canceled = create(:sale_order, user: customer, status: 'Canceled',
                                     subtotal: 100.0, total_order_value: 100.0)
      create(:sale_order_item, sale_order: canceled, product: product,
                               quantity: 6, unit_cost: 20.0, unit_final_price: 20.0)

      expect(pending_order.reload.status).to eq('Pending')
      # 3 + 4 + 5; Pending (2) y Canceled (6) quedan fuera.
      expect(units_sold).to eq(12)
      expect(product.total_sales_order).to eq(3)
    end
  end

  describe 'CASE H — editing a line still refreshes stats' do
    it 'keeps the existing line callback working on a confirmed order' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')
      expect(units_sold).to eq(3)

      order.sale_order_items.first.update!(quantity: 7)

      expect(units_sold).to eq(7)
    end
  end

  describe 'transaction safety' do
    it 'does not change stats when a status update fails validation' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')
      expect(units_sold).to eq(3)

      order.shipment.destroy
      order.reload

      expect(order.update(status: 'Delivered')).to be(false)
      expect(order.reload.status).to eq('Confirmed')
      expect(units_sold).to eq(3)
    end

    it 'does not change stats when a cancellation is blocked' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')
      expect(units_sold).to eq(3)

      expect { SaleOrders::CancelOrderService.new(order.reload).call }
        .to raise_error(SaleOrders::CancelOrderService::CancellationBlocked)

      expect(order.reload.status).to eq('Confirmed')
      expect(units_sold).to eq(3)
    end
  end

  describe 'scope of the recalculation' do
    it 'recalculates each affected product once, not once per line' do
      other_product = create(:product, skip_seed_inventory: true, selling_price: 20.0, minimum_price: 1.0)
      order = order_ready_for_transitions(quantity: 3)
      create(:sale_order_item, sale_order: order, product: product,
                               quantity: 1, unit_cost: 20.0, unit_final_price: 20.0)
      create(:sale_order_item, sale_order: order, product: other_product,
                               quantity: 2, unit_cost: 20.0, unit_final_price: 20.0)
      order.reload

      recalculated = []
      allow(Products::UpdateStatsService).to receive(:new).and_wrap_original do |original, product_arg|
        recalculated << product_arg.id
        original.call(product_arg)
      end

      order.update!(status: 'Confirmed')

      # Tres líneas, dos productos: dos recálculos.
      expect(recalculated.uniq.sort).to eq([product.id, other_product.id].sort)
      expect(recalculated.size).to eq(2)
    end

    it 'does not touch products outside the order' do
      untouched = create(:product, skip_seed_inventory: true, selling_price: 20.0, minimum_price: 1.0)
      order = order_ready_for_transitions(quantity: 3)
      before_stats = untouched.reload.updated_at

      order.update!(status: 'Confirmed')

      expect(untouched.reload.updated_at).to eq(before_stats)
    end

    it 'does not recalculate when the status moves within the active set' do
      order = order_ready_for_transitions(quantity: 3)
      order.update!(status: 'Confirmed')

      recalculated = []
      allow(Products::UpdateStatsService).to receive(:new).and_wrap_original do |original, product_arg|
        recalculated << product_arg.id
        original.call(product_arg)
      end

      order.update!(status: 'Preparing')

      # Confirmed y Preparing cuentan igual: no hay nada que recalcular.
      expect(recalculated).to be_empty
      expect(units_sold).to eq(3)
    end
  end

  describe 'the canonical status list' do
    it 'excludes Pending and Canceled and includes the four active statuses' do
      expect(SaleOrder::ACTIVE_SALE_STATUSES).to eq(['Confirmed', 'Preparing', 'In Transit', 'Delivered'])
      expect(SaleOrder::ACTIVE_SALE_STATUSES).not_to include('Pending')
      expect(SaleOrder::ACTIVE_SALE_STATUSES).not_to include('Canceled')
    end

    # El panel mide exactamente el mismo concepto, así que comparte la constante
    # en vez de llevar su propia copia.
    it 'is the single source the dashboard also uses' do
      expect(Dashboard::Metrics::SALE_STATUSES).to eq(SaleOrder::ACTIVE_SALE_STATUSES)
    end

    # Concepto distinto y deliberadamente NO unificado: para adeudo del cliente
    # una orden Pending sí cuenta (se debe), sólo se excluye la cancelada.
    it 'is not the same concept as active_for_totals' do
      expect(SaleOrder::NON_ACTIVE_TOTAL_STATUSES).to eq(['Canceled'])
      expect(SaleOrder::ACTIVE_SALE_STATUSES).not_to include('Pending')
    end
  end
end
