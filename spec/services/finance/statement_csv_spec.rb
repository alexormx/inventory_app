require 'rails_helper'

RSpec.describe Finance::StatementCsv do
  let(:product) { create(:product, skip_seed_inventory: true) }

  around { |example| travel_to(Time.zone.local(2026, 6, 15, 12)) { example.run } }

  it 'empieza con BOM, encabezados y una fila por concepto' do
    order = create(:sale_order)
    order.update_columns(total_order_value: 100, status: 'Delivered', order_date: Date.new(2026, 3, 10))
    item = create(:sale_order_item, sale_order: order, product: product, quantity: 1, unit_cost: 100,
                                    unit_final_price: 100, total_line_cost: 100)
    item.update_columns(total_line_cost: 100, unit_acquisition_cost: 60)
    order.update_columns(total_order_value: 100)
    payment = create(:payment, sale_order: order, amount: 100)
    payment.update_columns(paid_at: Date.new(2026, 3, 10), status: 'Completed')

    csv = described_class.new(Finance::MonthlyStatement.new(year: 2026).call).call

    expect(csv).to start_with("\uFEFF")
    expect(csv.encoding).to eq(Encoding::UTF_8)
    table = CSV.parse(csv.delete_prefix("\uFEFF"))
    expect(table.first).to eq(['Concepto', *%w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic], 'Total año'])
    expect(table.drop(1).map(&:first)).to eq(Finance::MonthlyStatement::ROW_LABELS.values)

    profit = table.find { |row| row.first == 'Utilidad del mes' }
    expect(profit[3]).to eq('40.0')
    expect(profit[7..12]).to all(eq('').or(be_nil))
    expect(profit[13]).to eq('40.0')
    count = table.find { |row| row.first == 'Órdenes concluidas' }
    expect(count[3]).to eq('1')
  end

  it 'vista histórica cierra con "Total"' do
    csv = described_class.new(Finance::MonthlyStatement.new(year: nil).call).call
    headers = CSV.parse(csv.delete_prefix("\uFEFF")).first
    expect(headers).to eq(%w[Concepto 2026 Total])
  end
end
