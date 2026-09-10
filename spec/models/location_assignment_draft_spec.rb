# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationAssignmentDraft, type: :model do
  let(:admin) { create(:user, :admin) }
  let(:other_admin) { create(:user, :admin) }
  let(:warehouse) { create(:inventory_location) }
  let!(:shelf) { create(:inventory_location, parent: warehouse) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def stock(count)
    create_list(:inventory, count, product: product, status: :available, inventory_location: nil)
  end

  def concurrently(count = 2)
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          outcomes << [:ok, yield(index)]
        rescue StandardError => e
          outcomes << [:error, e]
        end
      end
    end

    count.times { ready.pop }
    count.times { start << true }
    threads.each(&:join)
    count.times.map { outcomes.pop }
  end

  def assign_once(draft_id, actor_id)
    ActiveRecord::Base.transaction do
      draft = described_class.find(draft_id)
      lines = draft.consume! do |locked_lines|
        Inventories::BulkAssignLocationBatchService.call(
          lines: locked_lines,
          location_id: shelf.id,
          actor: User.find(actor_id)
        )
      end
      next :already_assigned if lines.empty?

      :assigned
    end
  end

  describe '.for' do
    it 'gives two tabs for one admin the same server-side draft' do
      ids = concurrently { described_class.for(admin).id }

      expect(ids.map(&:first)).to all(eq(:ok))
      expect(ids.map(&:last).uniq).to contain_exactly(described_class.find_by!(user: admin).id)
    end

    it 'isolates two administrators' do
      first = described_class.for(admin)
      second = described_class.for(other_admin)

      expect(first.id).not_to eq(second.id)
      expect(first.user).to eq(admin)
      expect(second.user).to eq(other_admin)
    end
  end

  describe 'expiration and cleanup' do
    it 'clears abandoned lines and location on the next access' do
      stock(2)
      draft = described_class.for(admin)
      draft.change_location(shelf.id)
      draft.add(product.id, 2)
      draft.update_columns(expires_at: 1.minute.ago, last_assigned_at: 1.minute.ago)

      refreshed = described_class.for(admin)

      expect(refreshed).to be_empty
      expect(refreshed.location).to be_nil
      expect(refreshed.last_assigned_at).to be_nil
      expect(refreshed.expires_at).to be > Time.current
    end

    it 'removes its finite draft and lines when the user is deleted' do
      stock(1)
      draft = described_class.for(admin)
      draft.add(product.id, 1)

      expect { admin.destroy! }
        .to change(described_class, :count).by(-1)
        .and change(LocationAssignmentDraftLine, :count).by(-1)
    end
  end

  describe 'concurrent additions from two tabs' do
    it 'rejects a rapid double Add that would exceed current inventory' do
      stock(5)
      draft = described_class.for(admin)

      outcomes = concurrently do
        described_class.find(draft.id).add(product.id, 3)
      end

      expect(draft.reload.pending_for(product.id)).to eq(3)
      expect(outcomes.count { |type, _| type == :ok }).to eq(1)
      expect(outcomes.filter_map { |type, value| value if type == :error }.map(&:class))
        .to contain_exactly(described_class::ExceedsAvailable)
    end

    it 'allows only five of ten rapid unit additions when five are assignable' do
      stock(5)
      draft = described_class.for(admin)

      outcomes = concurrently(10) do
        described_class.find(draft.id).add(product.id, 1)
      end

      expect(draft.reload.pending_for(product.id)).to eq(5)
      expect(outcomes.count { |type, _| type == :ok }).to eq(5)
      expect(outcomes.count { |type, value| type == :error && value.is_a?(described_class::ExceedsAvailable) }).to eq(5)
    end

    it 'makes two simultaneous Add All operations idempotent' do
      stock(5)
      draft = described_class.for(admin)

      outcomes = concurrently do
        described_class.find(draft.id).add_all(product.id)
      end

      expect(draft.reload.pending_for(product.id)).to eq(5)
      expect(outcomes.map(&:last)).to contain_exactly(5, 0)
    end
  end

  describe 'atomic consumption and assignment' do
    it 'lets only one of two simultaneous final posts consume and assign a shared draft' do
      stock(5)
      draft = described_class.for(admin)
      draft.change_location(shelf.id)
      draft.add_all(product.id)

      outcomes = concurrently { assign_once(draft.id, admin.id) }

      expect(outcomes.map(&:last)).to contain_exactly(:assigned, :already_assigned)
      expect(product.inventories.where(inventory_location: shelf).count).to eq(5)
      expect(InventoryEvent.where(event_type: 'physical_inventory_verification').count).to eq(5)
      expect(draft.reload).to be_empty
    end

    it 'assigns once across two admins and rolls the losing admin draft back intact' do
      stock(5)
      drafts = [admin, other_admin].map do |actor|
        described_class.for(actor).tap do |draft|
          draft.change_location(shelf.id)
          draft.add_all(product.id)
        end
      end

      outcomes = concurrently do |index|
        assign_once(drafts[index].id, [admin.id, other_admin.id][index])
      end

      expect(outcomes.count { |type, value| type == :ok && value == :assigned }).to eq(1)
      errors = outcomes.filter_map { |type, value| value if type == :error }
      expect(errors.map(&:class)).to contain_exactly(
        Inventories::BulkAssignLocationBatchService::InsufficientEligibleInventory
      )
      expect(product.inventories.where(inventory_location: shelf).count).to eq(5)
      expect(InventoryEvent.where(event_type: 'physical_inventory_verification').count).to eq(5)
      expect(drafts.sum { |draft| draft.reload.total_units }).to eq(5)
    end
  end
end
