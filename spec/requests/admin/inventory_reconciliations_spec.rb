# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin inventory reconciliations', type: :request do
  before { sign_in create(:user, :admin) }

  it 'reports a failed run instead of a silent zero' do
    failed = InventoryReconciliation::ReconcilePurchaseOrderLinksService::Result.new(
      destroyed_orphans: 0, created_missing: 0, errors: ['boom']
    )
    allow_any_instance_of(InventoryReconciliation::ReconcilePurchaseOrderLinksService)
      .to receive(:call).and_return(failed)

    post admin_inventory_reconciliations_path(mode: 'orphans')

    expect(flash[:alert]).to include('boom')
  end
end
