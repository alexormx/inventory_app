require 'rails_helper'
RSpec.describe 'Postal code autofill admin', type: :system, js: true do
  let!(:admin) { User.create!(email: 'admin@example.com', password: 'Password1!', role: 'admin', name: 'Admin', confirmed_at: Time.current) }
  let!(:customer) { User.create!(email: 'cust@example.com', password: 'Password1!', role: 'customer', name: 'Cliente', confirmed_at: Time.current) }

  before do
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'centro')
    PostalCode.create!(cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'modulo i')
  end

  it 'autocompleta en formulario admin de direcciones' do
    login_as admin, scope: :user
    visit admin_user_shipping_addresses_path(customer)
    fill_in 'CP', with: '36500'
    expect(page).to have_select('Colonia', options: include('Centro','Modulo I'), wait: 5)
    expect(find('#admin_addr_municipio').value).to match(/Irapuato/i)
    expect(find('#admin_addr_estado').value).to match(/Guanajuato/i)
  end
end
