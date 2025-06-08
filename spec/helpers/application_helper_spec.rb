require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#bootstrap_class_for' do
    it 'returns success class for notice' do
      expect(helper.bootstrap_class_for(:notice)).to eq('alert-success')
    end

    it 'returns info class for unknown key' do
      expect(helper.bootstrap_class_for(:other)).to eq('alert-info')
    end
  end

  describe '#currency_symbol_for' do
    it 'returns symbol when known' do
      expect(helper.currency_symbol_for('MXN')).to eq('$')
    end

    it 'returns code when unknown' do
      expect(helper.currency_symbol_for('XYZ')).to eq('XYZ')
    end
  end
end
