# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin sidebar active state (inventory adjustments)', type: :system do
  let!(:admin) { create(:user, :admin) }

  before do
    driven_by(:rack_test)
    sign_in admin
  end

  it 'marks Inventory Adjustments link active' do
    visit admin_inventory_adjustments_path
    expect(page).to have_css('a.nav-link.active span.sidebar-label', text: 'Inventory Adjustments')
  end

  it 'does not mark Inventory link active on adjustments page' do
    visit admin_inventory_adjustments_path
    expect(page).not_to have_css('a.nav-link.active span.sidebar-label', text: 'Inventory')
  end
end