# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplierSyncRun, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier_catalog_item).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_presence_of(:mode) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "state helpers" do
    it "marks a run as completed" do
      run = create(:supplier_sync_run)
      run.start!
      run.complete!(processed_count: 3)

      expect(run.reload.status).to eq("completed")
      expect(run.finished_at).to be_present
      expect(run.processed_count).to eq(3)
    end

    it "marks a run as failed and stores the sample" do
      run = create(:supplier_sync_run)
      run.fail!("boom")

      expect(run.reload.status).to eq("failed")
      expect(run.error_count).to eq(1)
      expect(run.error_samples).to include("boom")
    end
  end
end