# frozen_string_literal: true

class WhatsappRequestItem < ApplicationRecord
  belongs_to :whatsapp_request
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :product_id, uniqueness: { scope: :whatsapp_request_id }

  before_validation :snapshot_price, on: :create

  private

  def snapshot_price
    self.unit_price_snapshot ||= product&.selling_price
  end
end
