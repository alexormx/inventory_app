# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::ResponseSchema do
  it "con plantilla pide un objeto con exactamente sus llaves" do
    template = build(:category_attribute_template)
    attributes = described_class.for(template).dig(:properties, :attributes)
    expect(attributes[:type]).to eq("object")
    expect(attributes[:required]).to eq(template.attribute_keys)
  end

  # Un objeto vacío en modo estricto hace que el modelo escriba tabuladores sin
  # fin hasta el límite de tokens (visto en producción el 2026-10-06).
  it "sin plantilla pide una lista de pares clave–valor, nunca un objeto vacío" do
    attributes = described_class.for(nil).dig(:properties, :attributes)
    expect(attributes[:type]).to eq("array")
    item = attributes[:items]
    expect(item[:required]).to eq(%w[key value])
    expect(item[:additionalProperties]).to be(false)
  end
end
