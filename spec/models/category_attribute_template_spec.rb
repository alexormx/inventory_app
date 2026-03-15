# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryAttributeTemplate, type: :model do
  describe "validations" do
    subject { build(:category_attribute_template) }

    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_uniqueness_of(:category).case_insensitive }
    it { is_expected.to validate_presence_of(:attributes_schema) }
  end

  describe ".for_category" do
    let!(:diecast_template) { create(:category_attribute_template, category: "diecast") }

    it "finds by category name case-insensitive" do
      expect(described_class.for_category("Diecast")).to eq(diecast_template)
      expect(described_class.for_category("DIECAST")).to eq(diecast_template)
      expect(described_class.for_category("diecast")).to eq(diecast_template)
    end

    it "returns nil for missing category" do
      expect(described_class.for_category("figuras")).to be_nil
    end

    it "returns nil for inactive templates" do
      diecast_template.update!(active: false)
      expect(described_class.for_category("diecast")).to be_nil
    end
  end

  describe "#attribute_keys" do
    it "returns array of key strings" do
      template = build(:category_attribute_template)
      expect(template.attribute_keys).to include("color", "escala", "material")
    end
  end

  describe "#required_keys" do
    it "returns only required keys" do
      template = build(:category_attribute_template)
      expect(template.required_keys).to include("color", "escala")
      expect(template.required_keys).not_to include("apertura")
    end
  end

  describe "#schema_for" do
    it "returns schema entry for a key" do
      template = build(:category_attribute_template)
      schema = template.schema_for("color")
      expect(schema["label"]).to eq("Color")
      expect(schema["type"]).to eq("string")
      expect(schema["required"]).to be true
    end

    it "returns nil for unknown key" do
      template = build(:category_attribute_template)
      expect(template.schema_for("nonexistent")).to be_nil
    end
  end

  describe "normalize_category" do
    it "downcases and strips category" do
      template = create(:category_attribute_template, category: "  DieCAst  ")
      expect(template.category).to eq("diecast")
    end
  end
end
