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

  it "uses prompt version v8" do
    expect(result[:version]).to eq("v8")
  end

  it "no le manda a la IA identificadores internos" do
    user = result[:user]
    %w[TST-001 TOM-067 4904810123456].each { |code| expect(user).not_to include(code) }
    expect(user).not_to include("SKU:")
  end

  it "prohíbe identificadores, precios y URLs en el texto generado" do
    expect(result[:system]).to include("NUNCA incluyas SKU, códigos de proveedor, códigos de barras, precios ni URLs")
  end

  it "includes system prompt with Spanish instructions" do
    expect(result[:system]).to include("español de México")
    expect(result[:system]).to include("REGLAS ESTRICTAS")
    expect(result[:system]).to include("1 o 2 párrafos")
    expect(result[:system]).to include("La palabra \"null\" JAMÁS debe aparecer")
  end

  it "instructs a simple, factual, non-exaggerated tone" do
    system = result[:system]
    expect(system).to include("simple, profesional y factual")
    expect(system).to match(/PROHIBIDO usar frases exageradas/)
    %w[impresionante joya magnífico].each do |word|
      expect(system).to include(word)
    end
    expect(system).to include("no dejes pasar")
    expect(system).to include("pieza de conversación")
  end

  it "allows scale, color and material in the description but not package dimensions" do
    system = result[:system]
    expect(system).to include("La escala, el color y el material SÍ pueden mencionarse")
    expect(system).to match(/NO menciones en `description_es`.*peso/m)
  end

  it "includes product data in user prompt" do
    user = result[:user]
    expect(user).to include("067 Toyota Hilux")
    expect(user).to include("Tomica")
    # Ni el SKU ni el precio van al prompt: no deben terminar en el texto de la tienda.
    expect(user).not_to include("TST-001")
    expect(user).not_to include("199.99")
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

  it "includes natural description instructions" do
    user = result[:user]
    expect(user).to include("ESTILO OBLIGATORIO DE LA DESCRIPCIÓN")
    expect(user).to include("1 o 2 párrafos")
    expect(user).to include("No uses encabezados visibles")
    expect(user).to include("No escribas la palabra \"null\"")
    expect(user).to include("No uses HTML")
  end

  it "forbids exaggerated phrases in the user prompt style block" do
    user = result[:user]
    expect(user).to include("PROHIBIDO usar frases exageradas")
    expect(user).to include("impresionante")
    expect(user).to include("no dejes pasar")
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

  context "with supplier catalog context" do
    before do
      context[:supplier_context] = {
        catalog_item: {
          canonical_name: "Tomica Premium 20 Toyota Hilux",
          canonical_brand: "Tomica",
          canonical_series: "Tomica Premium",
          canonical_item_type: "diecast",
          canonical_release_date: "2024-03-01",
          canonical_price: 350.0,
          currency: "JPY",
          canonical_status: "available",
          barcode: "4904810123456",
          source_url: "https://example.com/product",
          description_raw: "A detailed scale model of the Toyota Hilux pickup truck.",
          details_payload: { "scale" => "1/64", "material" => "Zamac" }
        },
        sources: []
      }
    end

    it "includes supplier catalog data in prompt" do
      user = result[:user]
      expect(user).to include("DATOS DEL CATÁLOGO DEL PROVEEDOR")
      expect(user).to include("Tomica Premium 20 Toyota Hilux")
      expect(user).to include("Tomica Premium")
    end

    it "includes supplier description" do
      expect(result[:user]).to include("DESCRIPCIÓN DEL PROVEEDOR")
      expect(result[:user]).to include("Toyota Hilux pickup truck")
    end

    it "no manda código de barras, URL ni precio del proveedor, ni detalles que son códigos" do
      context[:supplier_context][:catalog_item][:details_payload] = { "scale" => "1/64", "jan_code" => "4904810999999",
                                                                      "Item Code" => "TKT-1", "price" => "1320" }
      user = result[:user]
      expect(user).not_to include("4904810123456")
      expect(user).not_to include("https://example.com/product")
      expect(user).not_to include("Precio proveedor")
      expect(user).not_to include("4904810999999")
      expect(user).not_to include("TKT-1")
      expect(user).not_to include("1320")
      expect(user).to include("scale: 1/64")
    end

    it "includes supplier technical details" do
      user = result[:user]
      expect(user).to include("DETALLES TÉCNICOS DEL PROVEEDOR")
      expect(user).to include("scale: 1/64")
      expect(user).to include("material: Zamac")
    end
  end

  context "without supplier catalog context" do
    before { context[:supplier_context] = nil }

    it "omits supplier catalog section" do
      expect(result[:user]).not_to include("DATOS DEL CATÁLOGO DEL PROVEEDOR")
    end
  end

  describe "v8" do
    it "prohíbe inventar origen, nacionalidad o historia y pide describir sólo lo visible" do
      system = result[:system]
      expect(system).to include("nacionalidad")
      expect(system).to include("visible con certeza en las fotos")
    end

    it "incluye los datos confirmados por la identificación con IA" do
      context[:ai_lookup] = { identification: { "brand" => "Tomica", "model_code" => "No. 23", "scale" => "1/62" },
                              launch_date: "2019-06", rarity_level: "poco_comun", rarity_reasons: ["Descontinuado"] }
      user = result[:user]
      expect(user).to include("DATOS CONFIRMADOS POR LA IDENTIFICACIÓN CON IA")
      expect(user).to include("- Código del fabricante: No. 23")
      expect(user).to include("- Fecha de lanzamiento: 2019-06")
      expect(user).to include("- Rareza: poco común (Descontinuado)")
    end

    it "omite las dimensiones en cero" do
      context[:dimensions] = { weight_gr: 0.0, length_cm: 16.0, width_cm: 0.0, height_cm: 0.0 }
      user = result[:user]
      expect(user).to include("Largo: 16.0cm")
      expect(user).not_to include("Peso")
      expect(user).not_to include("0.0g")
    end

    it "sin dimensiones no manda la sección" do
      context[:dimensions] = { weight_gr: 0.0, length_cm: 0.0, width_cm: 0.0, height_cm: 0.0 }
      expect(result[:user]).not_to include("DIMENSIONES DEL EMPAQUE")
    end
  end
end
