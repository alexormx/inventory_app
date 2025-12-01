# frozen_string_literal: true

class PreorderReservation < ApplicationRecord
  belongs_to :product
  belongs_to :user
  belongs_to :sale_order, optional: true

  # Rails 8 usa la nueva forma: enum :campo, { mapping }, default: :valor
  enum :status, { pending: 0, assigned: 1, completed: 2, cancelled: 3 }, default: :pending

  validates :quantity, numericality: { greater_than: 0 }

  before_validation :set_reserved_at, on: :create
  after_update :notify_if_assigned, if: -> { saved_change_to_status? && assigned? }

  scope :fifo_pending, -> { pending.order(:reserved_at, :id) }

  def position
    return nil unless pending?

    self.class.where(product_id: product_id, status: PreorderReservation.statuses[:pending])
        .where('reserved_at < ? OR (reserved_at = ? AND id < ?)', reserved_at, reserved_at, id)
        .count + 1
  end

  private

  def set_reserved_at
    self.reserved_at ||= Time.current
  end

  def notify_if_assigned
    PreorderMailer.assigned(id).deliver_later
  rescue StandardError => e
    Rails.logger.error "[PreorderReservation] notify_if_assigned error: #{e.class} #{e.message}"
  end
end
