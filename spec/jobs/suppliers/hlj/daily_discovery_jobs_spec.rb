# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HLJ daily discovery jobs" do
  before { allow(Suppliers::Hlj::WeeklyDiscoveryJob).to receive(:perform_now) }

  # El filtro de fechas de HLJ es remoto y ya falló una vez, dejando la corrida
  # diaria sin freno. Estos límites locales son la única garantía.
  it "bounds the recent arrivals job with local page and item limits" do
    Suppliers::Hlj::TomicaRecentArrivalsJob.perform_now

    expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_now).with(
      hash_including(
        max_pages: Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_PAGES,
        max_items: Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_ITEMS,
        detail_policy: "new_only"
      )
    )
  end

  it "bounds the recent additions job with local page and item limits" do
    Suppliers::Hlj::TomicaRecentAdditionsJob.perform_now

    expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_now).with(
      hash_including(
        max_pages: Suppliers::Hlj::TomicaRecentAdditionsJob::MAX_PAGES,
        max_items: Suppliers::Hlj::TomicaRecentAdditionsJob::MAX_ITEMS,
        detail_policy: "new_only"
      )
    )
  end

  it "keeps the limits small enough to stay well under an hour" do
    expect(Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_ITEMS).to be <= 500
    expect(Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_PAGES).to be <= 20
  end

  it "passes the limits and policy through to the discovery service" do
    allow(Suppliers::Hlj::WeeklyDiscoveryJob).to receive(:perform_now).and_call_original
    service = instance_double(Suppliers::Hlj::DiscoveryService, call: nil)
    allow(Suppliers::Hlj::DiscoveryService).to receive(:new).and_return(service)

    Suppliers::Hlj::TomicaRecentArrivalsJob.perform_now

    expect(Suppliers::Hlj::DiscoveryService).to have_received(:new).with(
      hash_including(
        max_pages: Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_PAGES,
        max_items: Suppliers::Hlj::TomicaRecentArrivalsJob::MAX_ITEMS,
        detail_policy: "new_only",
        max_duration_seconds: Suppliers::Hlj::DiscoveryService::DAILY_MAX_DURATION_SECONDS
      )
    )
  end

  # El sync completo semanal sí necesita recorrer todo, así que no debe heredar
  # el presupuesto corto de los jobs diarios.
  it "gives the weekly full sync a longer budget than the daily jobs" do
    expect(Suppliers::Hlj::DiscoveryService::DAILY_MAX_DURATION_SECONDS)
      .to be < Suppliers::Hlj::DiscoveryService::DEFAULT_MAX_DURATION_SECONDS
    expect(Suppliers::Hlj::DiscoveryService::DEFAULT_MAX_DURATION_SECONDS).to be <= 3600
  end
end
