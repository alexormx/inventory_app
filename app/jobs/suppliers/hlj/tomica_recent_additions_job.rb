# frozen_string_literal: true

module Suppliers
  module Hlj
    # Descubrimiento diario de altas Tomica.
    #
    # `date_added_within_days` es un filtro *remoto*: cuando HLJ deja de
    # honrarlo la búsqueda devuelve el catálogo completo. Los límites locales de
    # abajo son el único freno real, así que no deben quitarse.
    class TomicaRecentAdditionsJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      MAX_PAGES = Integer(ENV.fetch("HLJ_DAILY_MAX_PAGES", 5))
      MAX_ITEMS = Integer(ENV.fetch("HLJ_DAILY_MAX_ITEMS", 150))

      def perform
        Suppliers::Hlj::WeeklyDiscoveryJob.perform_now(
          mode: "tomica_recent_additions_daily",
          preset: "tomica_recent_additions",
          review_feed: "recent_additions",
          word: "tomica",
          date_added_within_days: 10,
          max_pages: MAX_PAGES,
          max_items: MAX_ITEMS,
          max_duration_seconds: Suppliers::Hlj::DiscoveryService::DAILY_MAX_DURATION_SECONDS,
          detail_policy: "new_only"
        )
      end
    end
  end
end
