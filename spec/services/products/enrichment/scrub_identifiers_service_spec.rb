# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::ScrubIdentifiersService do
  let(:product) do
    create(:product, skip_seed_inventory: true, product_sku: "PAS-TOM-0042",
                     supplier_product_code: "TKT-98765", barcode: "4904810742241")
  end

  subject(:scrubber) { described_class.new(product) }

  it "quita de una lista las entradas con SKU, código de proveedor, código de barras o sus etiquetas" do
    items = ["Escala 1:64", "SKU PAS-TOM-0042", "Ref. tkt-98765", "Código de barras 4904810742241",
             "JAN 1234567890123", "Color azul"]
    expect(scrubber.clean_list(items)).to eq(["Escala 1:64", "Color azul"])
  end

  it "quita de la descripción sólo la oración que menciona un identificador y conserva los párrafos" do
    text = "El Toyota Hilux de Tomica es un modelo 1:64. Su código de proveedor es TKT-98765.\n\n" \
           "Está hecho de metal die-cast. Ideal para vitrinas."
    expect(scrubber.clean_text(text)).to eq("El Toyota Hilux de Tomica es un modelo 1:64.\n\nEstá hecho de metal die-cast. Ideal para vitrinas.")
  end

  it "no toca textos sin identificadores" do
    text = "Modelo a escala del Nissan Skyline.\n\nColor rojo."
    expect(scrubber.clean_text(text)).to eq(text)
    expect(scrubber.clean_list(["Color rojo"])).to eq(["Color rojo"])
  end

  it "ignora identificadores demasiado cortos para no borrar palabras comunes" do
    product.update_columns(product_sku: "AB", supplier_product_code: nil, barcode: nil)
    expect(described_class.new(product).clean_list(["AB de metal", "Color rojo"])).to eq(["AB de metal", "Color rojo"])
  end

  it "reporta si quitó algo" do
    scrubber.clean_list(["Color rojo"])
    expect(scrubber.removed?).to be(false)
    scrubber.clean_list(["SKU PAS-TOM-0042"])
    expect(scrubber.removed?).to be(true)
  end
end
