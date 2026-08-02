# frozen_string_literal: true

module Suppliers
  module Hlj
    # Refresco diario de estado y precio del catálogo HLJ ya conocido.
    #
    # Sustituye al recorrido de detalle que hacían los jobs de descubrimiento:
    # aquí no se descarga HTML, solo lotes contra livePrice.
    class TomicaStatusSyncJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform(options = {})
        normalized = options.to_h.deep_symbolize_keys

        run = SupplierSyncRun.create!(
          source: "hlj",
          mode: normalized[:mode].presence || "hlj_status_sync",
          status: "queued",
          metadata: { "batch_size" => normalized[:batch_size], "max_items" => normalized[:max_items] }.compact
        )

        Suppliers::Hlj::StatusSyncService.new(
          run: run,
          batch_size: normalized[:batch_size],
          max_items: normalized[:max_items]
        ).call
      rescue StandardError => e
        run&.fail!(e.message) if run&.persisted? && !run.reload.status.in?(%w[completed failed cancelled])
        raise
      end
    end
  end
end
