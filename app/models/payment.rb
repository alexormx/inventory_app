class Payment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"

  enum :payment_method, [
    :tarjeta_de_credito,
    :efectivo,
    :transferencia_bancaria
]


  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: payment_methods.keys }
  validates :status, presence: true, inclusion: { in: %w[Pending Completed Failed Refunded] }

  before_save :set_paid_at_if_completed
  after_commit :update_sale_order_status_if_fully_paid



  private

  def update_sale_order_status
    sale_order.update_status_if_fully_paid!
  end

  def set_paid_at_if_completed
    self.paid_at = Time.current if status == "Completed" && paid_at.blank?
  end

  def update_sale_order_status_if_fully_paid
    sale_order&.update_status_if_fully_paid!
  end
end
