# frozen_string_literal: true

require "rails_helper"

# config/recurring.yml es el contrato de lo que Solid Queue agenda solo. Estas
# pruebas fijan que el backfill de TakaraTomyMall ya no se programe y, sobre
# todo, que la pausa no se haya llevado por delante ningún otro job.
RSpec.describe "Recurring schedule" do
  subject(:production_tasks) do
    YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).fetch("production")
  end

  it "no longer schedules the paused TakaraTomyMall weekly backfill" do
    expect(production_tasks).not_to have_key("suppliers_takara_tomy_mall_weekly_backfill")
  end

  it "does not reference the paused job class from any scheduled task" do
    scheduled_classes = production_tasks.values.map { |task| task["class"] }

    expect(scheduled_classes).not_to include("Suppliers::TakaraTomyMall::WeeklyBackfillJob")
  end

  it "leaves every unrelated supplier and maintenance schedule in place" do
    expect(production_tasks.keys).to contain_exactly(
      "products_reconcile_publication_daily",
      "suppliers_hlj_status_sync_daily",
      "suppliers_hlj_tomica_recent_additions_daily",
      "suppliers_hlj_tomica_recent_arrivals_daily",
      "suppliers_hlj_weekly_discovery",
      "suppliers_tomica_fandom_weekly_backfill",
      "visitor_logs_retention_daily",
      "whatsapp_requests_cleanup_drafts_daily"
    )
  end

  it "keeps the TomicaFandom weekly backfill on its original schedule" do
    expect(production_tasks.fetch("suppliers_tomica_fandom_weekly_backfill"))
      .to include("class" => "Suppliers::TomicaFandom::WeeklyBackfillJob", "schedule" => "0 7 * * 1")
  end
end
