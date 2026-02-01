# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationType, type: :model do
  describe 'validations' do
    subject { build(:location_type) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:color) }
    it { should validate_uniqueness_of(:code).case_insensitive }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_length_of(:code).is_at_most(50) }
  end

  describe 'associations' do
    it { should have_many(:inventory_locations) }
  end

  describe 'scopes' do
    let!(:active_type) { create(:location_type, active: true, position: 1) }
    let!(:inactive_type) { create(:location_type, active: false, position: 2) }

    describe '.active' do
      it 'returns only active types' do
        expect(described_class.active).to include(active_type)
        expect(described_class.active).not_to include(inactive_type)
      end
    end

    describe '.ordered' do
      let!(:first_type) { create(:location_type, position: 0, name: 'AAA') }
      let!(:second_type) { create(:location_type, position: 0, name: 'BBB') }

      it 'orders by position and then by name' do
        ordered = described_class.ordered
        expect(ordered.first).to eq(first_type)
      end
    end
  end

  describe 'code normalization' do
    it 'normalizes code to parameterized underscore format' do
      type = create(:location_type, code: 'Mi Tipo Especial')
      expect(type.code).to eq('mi_tipo_especial')
    end

    it 'handles already normalized codes' do
      type = create(:location_type, code: 'my_custom_type')
      expect(type.code).to eq('my_custom_type')
    end
  end

  describe 'class methods' do
    before do
      # Clear existing types
      described_class.delete_all
      create(:location_type, :warehouse, active: true)
      create(:location_type, :zone, active: true)
      create(:location_type, :shelf, active: false)
    end

    describe '.valid_codes' do
      it 'returns only active type codes' do
        codes = described_class.valid_codes
        expect(codes).to include('warehouse', 'zone')
        expect(codes).not_to include('shelf')
      end
    end

    describe '.options_for_select' do
      it 'returns array of [name, code] pairs for active types' do
        options = described_class.options_for_select
        expect(options).to include(['Bodega', 'warehouse'])
        expect(options).to include(['Zona', 'zone'])
        expect(options.flatten).not_to include('shelf')
      end
    end

    describe '.name_for' do
      it 'returns the name for a valid code' do
        expect(described_class.name_for('warehouse')).to eq('Bodega')
      end

      it 'returns humanized code for unknown code' do
        expect(described_class.name_for('unknown_type')).to eq('Unknown type')
      end
    end

    describe '.color_for' do
      it 'returns the color for a valid code' do
        expect(described_class.color_for('warehouse')).to eq('primary')
      end

      it 'returns secondary for unknown code' do
        expect(described_class.color_for('unknown')).to eq('secondary')
      end
    end

    describe '.icon_for' do
      it 'returns the icon for a valid code' do
        expect(described_class.icon_for('warehouse')).to eq('bi-building')
      end

      it 'returns default icon for unknown code' do
        expect(described_class.icon_for('unknown')).to eq('bi-geo-alt')
      end
    end

    describe '.seed_defaults!' do
      before { described_class.delete_all }

      it 'creates default types when none exist' do
        expect { described_class.seed_defaults! }.to change(described_class, :count).by(9)
      end

      it 'does not create types when some already exist' do
        create(:location_type)
        expect { described_class.seed_defaults! }.not_to change(described_class, :count)
      end
    end
  end

  describe '#display_name' do
    it 'returns name with code in parentheses' do
      type = build(:location_type, name: 'Bodega', code: 'warehouse')
      expect(type.display_name).to eq('Bodega (warehouse)')
    end
  end
end
