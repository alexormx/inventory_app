# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryEvent, type: :model do
  let(:inventory) { create(:inventory) }

  def physical_verification_metadata
    {
      'result' => 'found',
      'notes' => 'Verified on shelf',
      'actor_id' => 123,
      'actor_email' => 'admin@example.com',
      'actor_name' => 'Inventory Admin',
      'previous_status' => 'available',
      'new_status' => 'available',
      'previous_location_id' => nil,
      'new_location_id' => 456,
      'product_id' => inventory.product_id,
      'purchase_order_id' => inventory.purchase_order_id,
      'purchase_order_item_id' => inventory.purchase_order_item_id,
      'sale_order_id' => inventory.sale_order_id,
      'sale_order_item_id' => inventory.sale_order_item_id,
      'expected_updated_at' => inventory.updated_at.utc.iso8601(6),
      'verified_inventory_updated_at' => inventory.updated_at.utc.iso8601(6)
    }
  end

  it 'accepts a physical verification event with complete metadata' do
    event = described_class.new(
      inventory: inventory,
      product: inventory.product,
      event_type: 'physical_inventory_verification',
      metadata: physical_verification_metadata
    )

    expect(event).to be_valid
  end

  it 'requires complete metadata only for physical verification events' do
    metadata = physical_verification_metadata.except('sale_order_item_id')
    event = described_class.new(
      inventory: inventory,
      product: inventory.product,
      event_type: 'physical_inventory_verification',
      metadata: metadata
    )

    expect(event).not_to be_valid
    expect(event.errors[:metadata].join).to include('sale_order_item_id')
  end

  it 'rejects an unsupported physical verification result' do
    event = described_class.new(
      inventory: inventory,
      product: inventory.product,
      event_type: 'physical_inventory_verification',
      metadata: physical_verification_metadata.merge('result' => 'recounted')
    )

    expect(event).not_to be_valid
    expect(event.errors[:metadata]).to include('has an invalid verification result')
  end

  it 'does not impose physical verification metadata on historical event types' do
    event = described_class.new(
      inventory: inventory,
      product: inventory.product,
      event_type: 'status_change',
      metadata: {}
    )

    expect(event).to be_valid
  end
end
