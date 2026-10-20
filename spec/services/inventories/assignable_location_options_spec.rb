# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inventories::AssignableLocationOptions do
  let(:warehouse) { create(:inventory_location, name: 'Bodega A') }
  let(:shelf) { create(:inventory_location, name: 'Estante B03', parent: warehouse) }
  let(:other_shelf) { create(:inventory_location, name: 'Estante B04', parent: warehouse) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def stock(count, location:, status: :available)
    Array.new(count) { create(:inventory, product: product, status: status, inventory_location: location) }
  end

  def label_for(location)
    described_class.call.find { |(_label, id)| id == location.id }&.first
  end

  it 'enseña las piezas guardadas entre paréntesis' do
    stock(4, location: shelf)

    expect(label_for(shelf)).to eq("#{shelf.path_cache} (#{shelf.code}) (4 piezas)")
  end

  it 'singulariza una sola pieza' do
    stock(1, location: shelf)

    expect(label_for(shelf)).to end_with('(1 pieza)')
  end

  it 'enseña cero en una ubicación vacía' do
    other_shelf

    expect(label_for(other_shelf)).to end_with('(0 piezas)')
  end

  it 'no cuenta lo que hay en otra ubicación' do
    stock(4, location: shelf)
    stock(7, location: other_shelf)

    expect(label_for(shelf)).to end_with('(4 piezas)')
    expect(label_for(other_shelf)).to end_with('(7 piezas)')
  end

  # El mismo criterio que "Actualmente en esta ubicación": si los dos números
  # de la misma pantalla no coinciden, el operador cree que algo se perdió.
  it 'cuenta lo mismo que el resumen de la ubicación' do
    stock(3, location: shelf, status: :available)
    stock(2, location: shelf, status: :reserved)
    stock(1, location: shelf, status: :pre_reserved)

    expect(label_for(shelf)).to end_with("(#{Inventories::LocationInventorySummary.for(shelf).total_units} piezas)")
  end

  it 'ignora estatus que ya no están físicamente en bodega' do
    stock(2, location: shelf, status: :available)
    stock(5, location: shelf, status: :sold)

    expect(label_for(shelf)).to end_with('(2 piezas)')
  end

  it 'deja fuera las ubicaciones que son padre de otra' do
    shelf

    expect(described_class.call.map(&:last)).to include(shelf.id)
    expect(described_class.call.map(&:last)).not_to include(warehouse.id)
  end

  it 'no hace una consulta por ubicación' do
    stock(1, location: shelf)
    other_shelf
    create(:inventory_location, name: 'Estante B05', parent: warehouse)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { described_class.call }

    expect(queries).to be <= 3
  end
end
