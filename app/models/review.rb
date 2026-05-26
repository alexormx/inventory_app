# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :product
  belongs_to :user

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :body, presence: true, length: { minimum: 10, maximum: 5000 }
  validates :title, length: { maximum: 140 }
  validates :user_id, uniqueness: { scope: :product_id, message: 'ya ha reseñado este producto' }

  before_save :stamp_approved_at

  scope :visible, -> { approved.order(created_at: :desc) }

  # Did this user buy this product (delivered or earlier delivered) before reviewing?
  def self.user_purchased?(user, product)
    return false if user.blank? || product.blank?

    SaleOrderItem.joins(:sale_order)
                 .where(product_id: product.id, sale_orders: { user_id: user.id })
                 .exists?
  end

  private

  def stamp_approved_at
    if status_changed? && approved?
      self.approved_at ||= Time.current
    elsif status_changed? && !approved?
      self.approved_at = nil
    end
  end
end
