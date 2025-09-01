require 'rails_helper'
RSpec.describe Sepomex::Importer do
  let(:csv_path) { Rails.root.join('tmp/test_postal_codes.csv') }

  before do
    File.write(csv_path, <<~CSV)
cp,state,municipality,settlement,settlement_type
36500,Guanajuato,Irapuato,Centro,Colonia
36500,Guanajuato,Irapuato,Modulo I,Colonia
BADCP,Guanajuato,Irapuato,Fallo,Colonia
    CSV
  end

  after { File.delete(csv_path) if File.exist?(csv_path) }

  it 'importa solo filas válidas' do
    count = described_class.new(csv_path).call
    expect(count).to eq(2)
    expect(PostalCode.by_cp('36500').pluck(:settlement).sort).to eq(%w[centro modulo i])
  end
end
