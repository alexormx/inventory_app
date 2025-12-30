require 'rails_helper'

RSpec.describe 'Admin::InventoryAdjustments', type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }
  let(:product) { create(:product) }
  let(:adjustment) { create(:inventory_adjustment, status: 'draft') }

  before do
    login_as(admin, scope: :user)
  end

  describe 'PATCH /admin/inventory_adjustments/:id' do
    it 'persists nested lines' do
      patch admin_inventory_adjustment_path(adjustment), params: {
        inventory_adjustment: {
          note: 'Updated note',
          inventory_adjustment_lines_attributes: {
            '0' => {
              product_id: product.id,
              quantity: 2,
              direction: 'decrease',
              reason: 'scrap'
            }
          }
        }
      }

      expect(response).to redirect_to(admin_inventory_adjustment_path(adjustment))
      line = adjustment.reload.inventory_adjustment_lines.first
      expect(line).to have_attributes(
        product_id: product.id,
        quantity: 2,
        direction: 'decrease',
        reason: 'scrap'
      )
    end
  end
end
