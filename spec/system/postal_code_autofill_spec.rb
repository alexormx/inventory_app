require 'rails_helper'
RSpec.describe 'Postal code autofill', type: :system, js: true do
  let!(:user) { User.create!(email: 'test@example.com', password: 'Password1!', role: 'customer', name: 'Tester', confirmed_at: Time.current) }
  before do
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'centro')
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'modulo i')
  end

  it 'autocompleta municipio/estado y colonias en panel cliente' do
    login_as user, scope: :user
    visit shipping_addresses_path
    fill_in 'CP', with: '36500'
    # Esperar opciones
    expect(page).to have_select('Colonia', options: include('Centro', 'Modulo I'), wait: 5)
    expect(find('#cust_addr_municipio').value).to match(/Irapuato/i)
    expect(find('#cust_addr_estado').value).to match(/Guanajuato/i)
  end
end
