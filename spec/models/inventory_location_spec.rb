# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLocation, type: :model do
  # Ensure LocationTypes exist before running specs
  before(:all) do
    LocationType.seed_defaults! unless LocationType.exists?
  end

  describe 'validations' do
    subject { build(:inventory_location) }

    it { is_expected.to validate_presence_of(:name) }
    # Note: code is auto-generated, so presence validation passes due to before_validation callback
    it { is_expected.to validate_presence_of(:location_type) }
    it { is_expected.to validate_uniqueness_of(:code).case_insensitive }

    it 'validates location_type against LocationType records' do
      location = build(:inventory_location, location_type: 'invalid_type')
      expect(location).not_to be_valid
      expect(location.errors[:location_type]).to be_present
    end

    it 'is valid with valid attributes' do
      location = build(:inventory_location, :warehouse)
      expect(location).to be_valid
    end

    it 'is invalid without a name' do
      location = build(:inventory_location, name: nil)
      expect(location).not_to be_valid
    end

    it 'prevents self-referencing parent' do
      location = create(:inventory_location)
      location.parent_id = location.id
      expect(location).not_to be_valid
      expect(location.errors[:parent_id]).to include('no puede ser la misma ubicación')
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:parent).class_name('InventoryLocation').optional }
    it { is_expected.to have_many(:children).class_name('InventoryLocation').dependent(:destroy) }
  end

  describe 'hierarchy' do
    let!(:warehouse) { create(:inventory_location, :warehouse, name: 'Bodega Principal') }
    let!(:section_a) { create(:inventory_location, :section, name: 'Sección A', parent: warehouse) }
    let!(:section_b) { create(:inventory_location, :section, name: 'Sección B', parent: warehouse) }
    let!(:rack_1) { create(:inventory_location, :rack, name: 'Estante 1', parent: section_a) }
    let!(:level_1) { create(:inventory_location, :level, name: 'Nivel 1', parent: rack_1) }

    describe '#ancestors' do
      it 'returns empty array for root' do
        expect(warehouse.ancestors).to eq([])
      end

      it 'returns parent chain for nested location' do
        expect(level_1.ancestors).to eq([warehouse, section_a, rack_1])
      end
    end

    describe '#descendants' do
      it 'returns all descendants' do
        expect(warehouse.descendants).to contain_exactly(section_a, section_b, rack_1, level_1)
      end

      it 'returns empty for leaf nodes' do
        expect(level_1.descendants).to eq([])
      end
    end

    describe '#path' do
      it 'returns full path from root to self' do
        expect(level_1.path).to eq([warehouse, section_a, rack_1, level_1])
      end
    end

    describe '#full_path' do
      it 'returns path as string' do
        expect(level_1.full_path).to eq('Bodega Principal > Sección A > Estante 1 > Nivel 1')
      end
    end

    describe '#depth' do
      it 'calculates depth correctly' do
        expect(warehouse.depth).to eq(0)
        expect(section_a.depth).to eq(1)
        expect(rack_1.depth).to eq(2)
        expect(level_1.depth).to eq(3)
      end
    end

    describe '#root?' do
      it 'returns true for root locations' do
        expect(warehouse.root?).to be true
      end

      it 'returns false for nested locations' do
        expect(section_a.root?).to be false
      end
    end

    describe '#leaf?' do
      it 'returns false for locations with children' do
        expect(warehouse.leaf?).to be false
      end

      it 'returns true for locations without children' do
        expect(level_1.leaf?).to be true
      end
    end

    describe '#siblings' do
      it 'returns other children of same parent' do
        expect(section_a.siblings).to contain_exactly(section_b)
      end
    end
  end

  describe 'code generation' do
    it 'auto-generates code from name if blank' do
      location = create(:inventory_location, name: 'Mi Bodega Nueva', code: nil)
      expect(location.code).to be_present
      expect(location.code).to start_with('MI-BODEGA')
    end

    it 'includes parent code as prefix' do
      parent = create(:inventory_location, :warehouse, code: 'BOD-A')
      child = create(:inventory_location, :section, name: 'Sección 1', code: nil, parent: parent)
      expect(child.code).to start_with('BOD-A-')
    end
  end

  describe 'scopes' do
    let!(:active_warehouse) { create(:inventory_location, :warehouse, active: true) }
    let!(:inactive_warehouse) { create(:inventory_location, :warehouse, :inactive) }
    let!(:section) { create(:inventory_location, :section, parent: active_warehouse) }

    describe '.active' do
      it 'returns only active locations' do
        expect(InventoryLocation.active).to include(active_warehouse)
        expect(InventoryLocation.active).not_to include(inactive_warehouse)
      end
    end

    describe '.roots' do
      it 'returns only root locations' do
        expect(InventoryLocation.roots).to include(active_warehouse, inactive_warehouse)
        expect(InventoryLocation.roots).not_to include(section)
      end
    end

    describe '.by_type' do
      it 'filters by location type' do
        expect(InventoryLocation.by_type('warehouse')).to include(active_warehouse)
        expect(InventoryLocation.by_type('warehouse')).not_to include(section)
      end
    end
  end

  describe '.tree' do
    let!(:warehouse) { create(:inventory_location, :warehouse) }
    let!(:section) { create(:inventory_location, :section, parent: warehouse) }

    it 'returns nested tree structure' do
      tree = InventoryLocation.tree
      expect(tree.first[:id]).to eq(warehouse.id)
      expect(tree.first[:children].first[:id]).to eq(section.id)
    end
  end

  describe '.nested_options' do
    let!(:warehouse) { create(:inventory_location, :warehouse, name: 'Bodega A') }
    let!(:section) { create(:inventory_location, :section, name: 'Sección 1', parent: warehouse) }
    let!(:rack) { create(:inventory_location, :rack, name: 'Estante 1', parent: section) }

    it 'returns flat list with indentation' do
      options = InventoryLocation.nested_options
      expect(options).to include(['Bodega A', warehouse.id])
      expect(options).to include(['— Sección 1', section.id])
      expect(options).to include(['—— Estante 1', rack.id])
    end
  end

  describe '#type_name' do
    it 'returns Spanish name for type' do
      location = build(:inventory_location, location_type: 'warehouse')
      expect(location.type_name).to eq('Bodega')
    end
  end

  describe '#suggested_child_types' do
    it 'returns types below current type' do
      warehouse = build(:inventory_location, :warehouse)
      expect(warehouse.suggested_child_types).to include('zone', 'section', 'aisle')
      expect(warehouse.suggested_child_types).not_to include('warehouse')
    end
  end
end
