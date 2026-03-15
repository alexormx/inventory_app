# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::BuildPromptService do
  let(:context) do
    {
      product_id: 1,
      product_sku: "TST-001",
      product_name: "067 Toyota Hilux",
      brand: "Tomica",
      category: "diecast",
      description: nil,
      selling_price: 199.99,
      custom_attributes: { "color" => "Rojo" },
      dimensions: { weight_gr: 100.0, length_cm: 16.0, width_cm: 4.0, height_cm: 4.0 },
      barcode: "4904810123456",
      supplier_code: "TOM-067",
      launch_date: "2024-03-01",
      discontinued: false,
      template: {
        category: "diecast",
        schema: [
          { "key" => "color", "label" => "Color", "type" => "string", "required" => true, "example" => "Azul" },
          { "key" => "apertura", "label" => "Apertura", "type" => "boolean", "required" => false, "example" => "false" }
        ],
        keys: %w[color apertura],
        required: %w[color]
      }
    }
  end

  subject(:result) { described_class.new(context).call }

  it "returns a hash with system, user, and version" do
    expect(result).to include(:system, :user, :version)
  end

  it "uses prompt version v2" do
    expect(result[:version]).to eq("v2")
  end

  it "includes system prompt with Spanish instructions" do
    expect(result[:system]).to include("español de México")
    expect(result[:system]).to include("REGLAS ESTRICTAS")
    expect(result[:system]).to include("Resumen:")
    expect(result[:system]).to include("Puntos destacados:")
  end

  it "includes product data in user prompt" do
    user = result[:user]
    expect(user).to include("067 Toyota Hilux")
    expect(user).to include("TST-001")
    expect(user).to include("Tomica")
    expect(user).to include("199.99")
  end

  it "includes current attributes" do
    expect(result[:user]).to include("color: Rojo")
  end

  it "includes dimension data" do
    expect(result[:user]).to include("100.0g")
    expect(result[:user]).to include("16.0cm")
  end

  it "includes template instructions" do
    user = result[:user]
    expect(user).to include("ATRIBUTOS REQUERIDOS POR LA CATEGORÍA")
    expect(user).to include("color [string]")
    expect(user).to include("(OBLIGATORIO)")
    expect(user).to include("apertura [boolean]")
    expect(user).to include("(opcional)")
  end

  it "includes JSON schema instructions" do
    expect(result[:user]).to include("description_es")
    expect(result[:user]).to include("confidence_score")
  end

  it "includes the required description structure instructions" do
    user = result[:user]
    expect(user).to include("FORMATO OBLIGATORIO DE LA DESCRIPCIÓN")
    expect(user).to include("Ficha del modelo:")
    expect(user).to include("Historia y contexto:")
    expect(user).to include("No uses HTML")
  end

  context "without template" do
    before { context[:template] = nil }

    it "omits template instructions section" do
      expect(result[:user]).not_to include("ATRIBUTOS REQUERIDOS POR LA CATEGORÍA")
    end
  end

  context "without existing description" do
    before { context[:description] = nil }

    it "omits description section" do
      expect(result[:user]).not_to include("DESCRIPCIÓN ACTUAL")
    end
  end

  context "without custom attributes" do
    before { context[:custom_attributes] = {} }

    it "omits attributes section" do
      expect(result[:user]).not_to include("ATRIBUTOS ACTUALES")
    end
  end
end
