# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductDescriptionDraft, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:product) }
    it { is_expected.to belong_to(:published_by).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:product_id) }
  end

  describe "enum" do
    it "defines expected statuses" do
      expect(described_class.statuses.keys).to match_array(
        %w[queued generating draft_generated published rejected failed]
      )
    end
  end

  describe "scopes" do
    let!(:queued) { create(:product_description_draft, status: :queued) }
    let!(:generated) { create(:product_description_draft, :draft_generated) }
    let!(:published) { create(:product_description_draft, :published) }

    it ".reviewable returns only draft_generated" do
      expect(described_class.reviewable).to contain_exactly(generated)
    end

    it ".recent orders by created_at desc" do
      expect(described_class.recent.first).to eq(published)
    end
  end

  describe "#publishable?" do
    it "returns true for draft_generated with content" do
      draft = build(:product_description_draft, :draft_generated)
      expect(draft.publishable?).to be true
    end

    it "returns false for queued" do
      draft = build(:product_description_draft, status: :queued)
      expect(draft.publishable?).to be false
    end

    it "returns false for draft_generated without content" do
      draft = build(:product_description_draft, status: :draft_generated, draft_content: nil)
      expect(draft.publishable?).to be false
    end
  end

  describe "#total_tokens" do
    it "sums input and output tokens" do
      draft = build(:product_description_draft, tokens_input: 500, tokens_output: 300)
      expect(draft.total_tokens).to eq(800)
    end

    it "handles nil tokens" do
      draft = build(:product_description_draft, tokens_input: nil, tokens_output: nil)
      expect(draft.total_tokens).to eq(0)
    end
  end

  describe "#snapshot_original_data" do
    it "saves the product description and attributes on create" do
      product = create(:product, description: "Old description", custom_attributes: { "color" => "Red" })
      draft = product.description_drafts.create!(status: :queued)
      expect(draft.original_description).to eq("Old description")
      expect(draft.original_attributes).to eq({ "color" => "Red" })
    end
  end
end
