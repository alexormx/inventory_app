require 'rails_helper'

RSpec.describe StatusHelper, type: :helper do
  describe '#status_badge_class' do
    it 'returns success class for Delivered' do
      expect(helper.status_badge_class('Delivered')).to eq('bg-success')
    end

    it 'returns secondary class for unknown status' do
      expect(helper.status_badge_class('Other')).to eq('bg-secondary')
    end
  end
end
