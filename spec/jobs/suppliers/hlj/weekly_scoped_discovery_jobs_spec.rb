# frozen_string_literal: true

require "rails_helper"

# El sync semanal corría sin filtros sobre todo HLJ (~35 000 páginas): se
# cortaba al llegar a la hora, siempre en las mismas primeras páginas, y
# llevaba al worker de 512 MB a R14 cada lunes. Ahora sólo cubre Tomica y
# autos, que es lo que se vende.
RSpec.describe "HLJ weekly scoped discovery jobs" do
  before { allow(Suppliers::Hlj::WeeklyDiscoveryJob).to receive(:perform_now) }

  describe Suppliers::Hlj::TomicaWeeklySyncJob do
    it "crawls only the tomica search, fetching detail pages just for new items" do
      described_class.perform_now

      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_now).with(
        hash_including(word: "tomica", detail_policy: "new_only", max_pages: described_class::MAX_PAGES)
      )
    end

    it "keeps the page cap close to the size of the tomica catalog, not all of HLJ" do
      expect(described_class::MAX_PAGES).to be_between(200, 400)
    end
  end

  describe Suppliers::Hlj::CarsRecentAdditionsJob do
    it "crawls only recent Cars & Bikes additions with a daily-sized budget" do
      described_class.perform_now

      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_now).with(
        hash_including(
          genre_codes: ["Cars & Bikes"],
          date_added_within_days: 14,
          detail_policy: "new_only",
          max_pages: described_class::MAX_PAGES,
          max_items: described_class::MAX_ITEMS,
          max_duration_seconds: Suppliers::Hlj::DiscoveryService::DAILY_MAX_DURATION_SECONDS
        )
      )
    end

    # El filtro de fecha es remoto; si HLJ lo ignora, el tope local es el único freno.
    it "bounds the crawl locally in case HLJ ignores the date filter" do
      expect(described_class::MAX_PAGES).to be <= 20
      expect(described_class::MAX_ITEMS).to be <= 500
    end
  end

  describe "config/recurring.yml" do
    let(:tasks) { YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).fetch("production") }
    let(:classes) { tasks.values.map { |task| task["class"] } }

    it "never schedules the unfiltered HLJ crawl directly" do
      expect(classes).not_to include("Suppliers::Hlj::WeeklyDiscoveryJob")
    end

    it "schedules the tomica and cars weekly jobs" do
      expect(classes).to include("Suppliers::Hlj::TomicaWeeklySyncJob", "Suppliers::Hlj::CarsRecentAdditionsJob")
    end
  end
end
