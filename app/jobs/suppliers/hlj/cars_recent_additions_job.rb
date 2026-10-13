# frozen_string_literal: true

module Suppliers
  module Hlj
    # Altas recientes de autos de cualquier marca (género "Cars & Bikes").
    #
    # El género completo son ~3 100 páginas, así que sólo se mira lo agregado
    # en las últimas dos semanas. `date_added_within_days` es un filtro
    # *remoto*: si HLJ deja de honrarlo la búsqueda devuelve el género entero,
    # y los límites locales de abajo son el único freno real.
    class CarsRecentAdditionsJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      MAX_PAGES = Integer(ENV.fetch('HLJ_CARS_WEEKLY_MAX_PAGES', 10))
      MAX_ITEMS = Integer(ENV.fetch('HLJ_CARS_WEEKLY_MAX_ITEMS', 250))

      def perform
        Suppliers::Hlj::WeeklyDiscoveryJob.perform_now(
          mode: 'cars_recent_additions_weekly',
          preset: 'cars_recent_additions',
          review_feed: 'recent_additions',
          genre_codes: ['Cars & Bikes'],
          date_added_within_days: 14,
          max_pages: MAX_PAGES,
          max_items: MAX_ITEMS,
          max_duration_seconds: Suppliers::Hlj::DiscoveryService::DAILY_MAX_DURATION_SECONDS,
          detail_policy: 'new_only'
        )
      end
    end
  end
end
