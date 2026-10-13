# frozen_string_literal: true

module Suppliers
  module Hlj
    # Recorrido semanal de todo el catálogo Tomica de HLJ (~225 páginas).
    #
    # Sustituye al sync sin filtros, que barría las ~35 000 páginas de HLJ, se
    # cortaba al llegar a la hora siempre en las mismas primeras páginas y
    # llevaba al worker de 512 MB a R14. Con `new_only` los ítems ya conocidos
    # se actualizan desde el listado y sólo se descarga el detalle de los nuevos.
    class TomicaWeeklySyncJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      MAX_PAGES = Integer(ENV.fetch('HLJ_TOMICA_WEEKLY_MAX_PAGES', 300))

      def perform
        Suppliers::Hlj::WeeklyDiscoveryJob.perform_now(
          mode: 'tomica_weekly_sync',
          preset: 'tomica',
          word: 'tomica',
          max_pages: MAX_PAGES,
          page_anomaly_threshold: MAX_PAGES,
          detail_policy: 'new_only'
        )
      end
    end
  end
end
