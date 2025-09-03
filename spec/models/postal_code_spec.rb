require 'rails_helper'
RSpec.describe PostalCode, type: :model do
  it 'normaliza campos a minúsculas y nil para vacíos/nan' do
    pc = described_class.new(cp: ' 36500 ', state: 'Guanajuato', municipality: 'Irapuato', settlement: 'Centro', settlement_type: ' NAN ')
    pc.validate
    expect(pc.cp).to eq('36500')
    expect(pc.state).to eq('guanajuato')
    expect(pc.municipality).to eq('irapuato')
    expect(pc.settlement).to eq('centro')
    expect(pc.settlement_type).to be_nil
  end

  it 'scope by_cp funciona' do
    described_class.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'centro')
    expect(PostalCode.by_cp('36500').count).to eq(1)
  end

  it 'valida cp de 5 dígitos' do
    pc = described_class.new(cp: '1234', state: 'a', municipality: 'b', settlement: 'c')
    expect(pc).not_to be_valid
    pc.cp = '01234'
    pc.validate
    expect(pc.errors[:cp]).to be_empty
  end
end
