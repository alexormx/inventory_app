class Payment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: %w[CreditCard Cash BankTransfer] }
  validates :status, presence: true, inclusion: { in: %w[Pending Completed Failed Refunded] }

  before_save :set_paid_at_if_completed

  private

  def update_sale_order_status
    sale_order.update_status_if_fully_paid!
  end
end
