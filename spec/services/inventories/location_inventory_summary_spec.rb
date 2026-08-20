# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inventories::LocationInventorySummary do
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }
  let(:other_shelf) { create(:inventory_location, name: 'Estante B04', parent: warehouse) }
  let(:product_a) { create(:product, skip_seed_inventory: true, product_name: 'Alfa') }
  let(:product_b) { create(:product, skip_seed_inventory: true, product_name: 'Bravo') }

  def stock(product, count, location:, status: :available)
    Array.new(count) { create(:inventory, product: product, status: status, inventory_location: location) }
  end

  it 'no consulta nada cuando no hay ubicación elegida' do
    summary = described_class.for(nil)

    expect(summary).not_to be_present
    expect(summary.lines).to eq([])
    expect(summary.total_units).to eq(0)
    expect(summary.product_count).to eq(0)
  end

  it 'agrupa por producto sólo lo de esa ubicación' do
    stock(product_a, 4, location: shelf)
    stock(product_b, 2, location: shelf)
    stock(product_a, 7, location: other_shelf)

    summary = described_class.for(shelf)

    expect(summary.total_units).to eq(6)
    expect(summary.product_count).to eq(2)
    expect(summary.lines.map { |l| [l.product.id, l.total] })
      .to contain_exactly([product_a.id, 4], [product_b.id, 2])
  end

  it 'desglosa por estatus físico' do
    stock(product_a, 3, location: shelf, status: :available)
    stock(product_a, 2, location: shelf, status: :reserved)
    stock(product_b, 1, location: shelf, status: :pre_reserved)

    summary = described_class.for(shelf)

    expect(summary.available_units).to eq(3)
    expect(summary.reserved_units).to eq(2)
    expect(summary.in_transit_units).to eq(1)
    expect(summary.total_units).to eq(6)
  end

  # Vendido o dado de baja no está físicamente en el estante aunque conserve el
  # id de ubicación: la pantalla es un inventario físico, no un histórico.
  it 'deja fuera los estatus que no representan mercancía en el estante' do
    stock(product_a, 2, location: shelf, status: :available)
    stock(product_b, 5, location: shelf, status: :sold)

    summary = described_class.for(shelf)

    expect(summary.total_units).to eq(2)
    expect(summary.lines.map { |l| l.product.id }).to eq([product_a.id])
  end

  it 'ordena por nombre para que la lista no baile entre recargas' do
    zeta = create(:product, skip_seed_inventory: true, product_name: 'Zeta')
    stock(zeta, 1, location: shelf)
    stock(product_a, 1, location: shelf)
    stock(product_b, 1, location: shelf)

    expect(described_class.for(shelf).lines.map { |l| l.product.product_name })
      .to eq(%w[Alfa Bravo Zeta])
  end

  # Con una consulta por producto o por imagen, un estante lleno tumbaría el dyno.
  # Lo que se fija no es un número mágico sino que el coste NO crece con el
  # tamaño del estante: mismas consultas con 3 productos que con 12.
  it 'consulta un número constante de veces, no una por producto' do
    def count_queries
      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:sql].start_with?('BEGIN', 'COMMIT')
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
      queries
    end

    def fill(location, product_count)
      product_count.times do |i|
        product = create(:product, skip_seed_inventory: true, product_name: "Producto #{location.id}-#{i}")
        stock(product, 2, location: location)
      end
    end

    fill(shelf, 3)
    fill(other_shelf, 12)

    small = count_queries { described_class.for(shelf).lines.each { |l| l.product.product_name } }
    big = count_queries { described_class.for(other_shelf).lines.each { |l| l.product.product_name } }

    expect(big.size).to eq(small.size), "el coste crece con el estante:\n#{(big - small).join("\n")}"
  end
end
