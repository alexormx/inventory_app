# frozen_string_literal: true

# Job para asignar automáticamente inventario disponible a Sale Orders pendientes.
# Se ejecuta periódicamente o cuando se dispara por un evento (ej: recepción de PO).
#
# Uso manual:
#   InventoryAutoAssignmentJob.perform_now
#
# Programado (en config/schedule.rb con whenever o similar):
#   every 1.hour do
#     runner "InventoryAutoAssignmentJob.perform_now"
#   end
#
class InventoryAutoAssignmentJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(triggered_by: 'job_scheduled', sale_order_ids: nil)
    Rails.logger.info "[InventoryAutoAssignmentJob] Starting auto-assignment (triggered_by: #{triggered_by})"

    result = SaleOrders::AutoAssignInventoryService.new(
      triggered_by: triggered_by,
      dry_run: false,
      sale_order_ids: sale_order_ids
    ).call

    if result.success?
      Rails.logger.info "[InventoryAutoAssignmentJob] Completed: #{result.assigned_count} assigned, #{result.pending_count} still pending"
    else
      Rails.logger.warn "[InventoryAutoAssignmentJob] Completed with errors: #{result.errors.join(', ')}"
    end

    result
  end
end
