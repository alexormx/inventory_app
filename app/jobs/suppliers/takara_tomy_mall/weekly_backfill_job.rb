# frozen_string_literal: true

module Suppliers
  module TakaraTomyMall
    class WeeklyBackfillJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      # Integración en pausa. El endpoint de TakaraTomyMall acepta la conexión
      # TCP y el handshake TLS, pero no devuelve ningún byte hasta que salta
      # Net::ReadTimeout; se reprodujo igual desde la red local y desde Heroku,
      # y no hay ninguna respuesta exitosa registrada. La implementación se
      # conserva intacta para reactivarla: basta poner ENABLED = true y
      # restaurar la entrada en config/recurring.yml. No requiere migración.
      ENABLED = false

      def perform
        # Salida temprana antes de crear el SupplierSyncRun, de recorrer el
        # catálogo o de abrir cualquier conexión: así un job ya encolado que se
        # vuelva a reclamar tras un reinicio termina limpio en vez de reintentar.
        unless ENABLED
          Rails.logger.info("[TakaraTomyMall] weekly backfill is paused; skipping run")
          return
        end

        run = SupplierSyncRun.create!(source: "takaratomy_mall", mode: "weekly_backfill", status: "queued")
        run.start!

        processed = 0
        updated = 0
        skipped = 0
        errors = []

        SupplierCatalogItem.where.not(barcode: [nil, ""]).find_each do |catalog_item|
          processed += 1
          result = Suppliers::TakaraTomyMall::BackfillItemService.new(catalog_item).call
          updated += 1 if result.changed
        rescue StandardError => e
          skipped += 1
          errors << "#{catalog_item.id}: #{e.message}"
        end

        run.complete!(
          processed_count: processed,
          updated_count: updated,
          skipped_count: skipped,
          error_count: errors.size,
          error_samples: errors.first(10),
          metadata: { timezone: "America/Mexico_City" }
        )
      end
    end
  end
end