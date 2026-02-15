# frozen_string_literal: true

module PurchaseOrders
  class RecalculateAllAlphaCostsJob < ApplicationJob
    queue_as :default

    # Placeholder: recalcula campos alpha_cost / compose_cost de cada PurchaseOrderItem
    # Estrategia:
    #  - Iterar en batches para no consumir demasiada memoria.
    #  - Llamar a un servicio (si existiera) o realizar un cálculo simple provisional.
    #  - Guardar contadores y actualizar MaintenanceRun.
    #  - Evitar callbacks pesados usando update_columns cuando sólo cambiamos costos.
    def perform(run_id)
      run = MaintenanceRun.find_by(id: run_id)
      processed = 0
      updated = 0

      scope = if defined?(PurchaseOrderItem)
                PurchaseOrderItem.all
              else
                []
              end

      total = scope.respond_to?(:count) ? scope.count : 0

      scope.find_in_batches(batch_size: 200) do |batch|
        batch.each do |item|
          processed += 1
          begin
            attrs = recompute_costs_for(item)
            if attrs.any?
              item.update_columns(attrs)
              updated += 1
            end
          rescue StandardError => e
            Rails.logger.error("RecalculateAllAlphaCostsJob item=#{item.id} error=#{e.class} #{e.message}")
          end
        end
        touch_progress(run, processed: processed, total: total, updated: updated)
      end

      run&.update!(status: :completed, finished_at: Time.current, stats: { total: total, processed: processed, updated: updated }.to_json)
    rescue StandardError => e
      run&.update!(status: :failed, finished_at: Time.current, error: "#{e.class}: #{e.message}")
      Rails.logger.error("RecalculateAllAlphaCostsJob fatal error: #{e.class} #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      raise
    end

    private

    # Cálculo provisional: si hay quantity y unit_cost, alpha_cost = quantity * unit_cost.
    # compose_cost podría ser alpha_cost * 1.05 como placeholder.
    # Sólo actualizamos si cambia el valor para minimizar writes.
    def recompute_costs_for(item)
      return {} unless item.respond_to?(:quantity) && item.respond_to?(:unit_cost)
      return {} unless item.respond_to?(:alpha_cost) && item.respond_to?(:compose_cost)

      qty = item.quantity.to_f
      unit = item.unit_cost.to_f
      new_alpha = (qty * unit).round(2)
      new_compose = (new_alpha * 1.05).round(2)
      changes = {}
      changes[:alpha_cost] = new_alpha if item.alpha_cost.to_f != new_alpha
      changes[:compose_cost] = new_compose if item.compose_cost.to_f != new_compose
      changes
    end

    def touch_progress(run, processed:, total:, updated:)
      return unless run && (processed % 500).zero? # throttling cada 500 para no spamear DB

      run.update_columns(stats: { total: total, processed: processed, updated: updated, at: Time.current.to_i }.to_json)
    end
  end
end
