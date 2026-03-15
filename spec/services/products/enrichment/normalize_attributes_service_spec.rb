# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::NormalizeAttributesService do
  let(:template) { create(:category_attribute_template, category: "diecast") }

  describe "#call" do
    it "normalizes boolean values" do
      raw = { "apertura" => "sí", "suspension" => "no" }
      result = described_class.new(raw, template).call

      expect(result["apertura"]).to eq("true")
      expect(result["suspension"]).to eq("false")
    end

    it "normalizes boolean yes/no variants" do
      raw = { "apertura" => "yes", "suspension" => "false" }
      result = described_class.new(raw, template).call

      expect(result["apertura"]).to eq("true")
      expect(result["suspension"]).to eq("false")
    end

    it "normalizes string values by stripping whitespace" do
      raw = { "color" => "  Azul metálico  ", "escala" => "1:64" }
      result = described_class.new(raw, template).call

      expect(result["color"]).to eq("Azul metálico")
      expect(result["escala"]).to eq("1:64")
    end

    it "handles null/nil values" do
      raw = { "color" => "null", "escala" => nil, "material" => "" }
      result = described_class.new(raw, template).call

      expect(result["color"]).to be_nil
      expect(result["escala"]).to be_nil
      expect(result["material"]).to be_nil
    end

    it "preserves extra keys not in template" do
      raw = { "color" => "Rojo", "unknown_attr" => "some value" }
      result = described_class.new(raw, template).call

      expect(result["color"]).to eq("Rojo")
      expect(result["unknown_attr"]).to eq("some value")
    end

    it "includes all template keys even if missing from raw" do
      raw = { "color" => "Rojo" }
      result = described_class.new(raw, template).call

      expect(result).to have_key("escala")
      expect(result["escala"]).to be_nil
    end

    context "without template" do
      it "returns raw attributes unchanged" do
        raw = { "foo" => "bar", "baz" => "123" }
        result = described_class.new(raw, nil).call

        expect(result).to eq(raw)
      end
    end

    context "with nil raw attributes" do
      it "returns template keys with nil values" do
        result = described_class.new(nil, template).call

        expect(result).to have_key("color")
        expect(result["color"]).to be_nil
      end
    end
  end
end
