# frozen_string_literal: true

class InventoryAssignmentLog < ApplicationRecord
  belongs_to :sale_order, optional: true
  belongs_to :sale_order_item, optional: true
  belongs_to :product, optional: true
  belongs_to :inventory, optional: true

  enum :assignment_type, {
    auto_assignment: 0,       # Asignación automática por job/hook
    manual_assignment: 1,     # Asignación manual por admin
    checkout_assignment: 2,   # Asignación durante checkout
    reconciliation: 3,        # Asignación por reconciliación
    preorder_fulfillment: 4   # Cumplimiento de preventa
  }

  TRIGGERS = %w[
    system
    job_scheduled
    job_manual
    inventory_created
    inventory_status_changed
    po_received
    admin_action
    checkout
  ].freeze

  validates :triggered_by, inclusion: { in: TRIGGERS }
  validates :assigned_at, presence: true
  validates :quantity_assigned, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_pending, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(assigned_at: :desc) }
  scope :today, -> { where(assigned_at: Time.current.beginning_of_day..) }
  scope :this_week, -> { where(assigned_at: 1.week.ago..) }

  # Log de resumen para una corrida de asignación
  def self.log_assignment_run(triggered_by:, assignments:, notes: nil)
    return if assignments.empty?

    assignments.each do |assignment|
      create!(
        sale_order: assignment[:sale_order],
        sale_order_item: assignment[:sale_order_item],
        product: assignment[:product],
        inventory: assignment[:inventory],
        assigned_at: Time.current,
        assignment_type: assignment[:type] || :auto_assignment,
        triggered_by: triggered_by,
        quantity_assigned: assignment[:quantity_assigned] || 1,
        quantity_pending: assignment[:quantity_pending] || 0,
        notes: notes || assignment[:notes]
      )
    end
  end
end
