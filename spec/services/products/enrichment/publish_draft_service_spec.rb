# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::PublishDraftService do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product, skip_seed_inventory: true, description: "Old desc", custom_attributes: { "color" => "Rojo" }) }
  let(:draft) do
    create(:product_description_draft, :draft_generated,
           product: product,
           draft_content: "New enriched description.",
           draft_attributes: { "color" => "Azul", "escala" => "1:64" })
  end

  subject(:service) { described_class.new(draft, published_by: admin) }

  describe "#call" do
    it "updates product description" do
      service.call
      product.reload
      expect(product.description).to eq("New enriched description.")
    end

    it "updates product custom_attributes" do
      service.call
      product.reload
      expect(product.custom_attributes).to include("color" => "Azul", "escala" => "1:64")
    end

    it "marks draft as published" do
      service.call
      draft.reload
      expect(draft.status).to eq("published")
      expect(draft.published_at).to be_present
      expect(draft.published_by).to eq(admin)
    end

    it "rejects other pending drafts for the product" do
      other_draft = create(:product_description_draft, :draft_generated, product: product)
      queued_draft = create(:product_description_draft, product: product, status: :queued)

      service.call

      expect(other_draft.reload.status).to eq("rejected")
      expect(queued_draft.reload.status).to eq("rejected")
    end

    it "does not reject already failed or rejected drafts" do
      failed_draft = create(:product_description_draft, :failed, product: product)
      rejected_draft = create(:product_description_draft, :rejected, product: product)

      service.call

      expect(failed_draft.reload.status).to eq("failed")
      expect(rejected_draft.reload.status).to eq("rejected")
    end

    it "returns the published draft" do
      result = service.call
      expect(result).to eq(draft)
      expect(result.status).to eq("published")
    end

    context "when draft_attributes is blank" do
      before { draft.update!(draft_attributes: {}) }

      it "preserves existing product custom_attributes" do
        service.call
        product.reload
        expect(product.custom_attributes).to eq({ "color" => "Rojo" })
      end
    end
  end

  describe "validation errors" do
    it "raises error if draft is not publishable" do
      draft.update!(status: :queued)
      expect { service.call }.to raise_error(
        Products::Enrichment::PublishDraftService::PublishError,
        /not in publishable state/
      )
    end

    it "raises error if draft content is blank" do
      draft.update!(draft_content: nil)
      expect { service.call }.to raise_error(
        Products::Enrichment::PublishDraftService::PublishError,
        /not in publishable state/
      )
    end

    it "raises error if published_by is nil" do
      svc = described_class.new(draft, published_by: nil)
      expect { svc.call }.to raise_error(
        Products::Enrichment::PublishDraftService::PublishError,
        /Published_by user is required/
      )
    end
  end
end
