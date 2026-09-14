# frozen_string_literal: true

require "rails_helper"

# La integración de TakaraTomyMall quedó en pausa porque el endpoint dejó de
# responder y ninguna corrida semanal llegó nunca a completarse. Estas pruebas
# fijan el contrato de esa pausa: un job que ya estaba encolado y se vuelve a
# reclamar tras un reinicio tiene que terminar limpio, sin crear la corrida,
# sin recorrer el catálogo y sin abrir ninguna conexión de salida.
RSpec.describe Suppliers::TakaraTomyMall::WeeklyBackfillJob do
  it "keeps the integration disabled" do
    expect(described_class::ENABLED).to be false
  end

  it "does not create a SupplierSyncRun" do
    expect { described_class.perform_now }.not_to change(SupplierSyncRun, :count)
  end

  it "does not iterate the supplier catalog" do
    expect(SupplierCatalogItem).not_to receive(:where)

    described_class.perform_now
  end

  it "does not invoke the per-item backfill service" do
    expect(Suppliers::TakaraTomyMall::BackfillItemService).not_to receive(:new)

    described_class.perform_now
  end

  it "finishes cleanly instead of raising or retrying" do
    expect { described_class.perform_now }.not_to raise_error
  end
end
