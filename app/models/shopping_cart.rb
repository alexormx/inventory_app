# frozen_string_literal: true

# Persistence foundation for the future shopping cart. Nothing in the
# storefront writes to this table yet - session[:cart] (see app/models/cart.rb)
# remains the live source of truth until import/reconciliation ships in a
# later PR. These are lifecycle invariants only; no reconciliation service.
class ShoppingCart < ApplicationRecord
  STATUSES = %w[active converted merged cleared].freeze

  belongs_to :user, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :merged_into_cart, class_name: 'ShoppingCart', optional: true
  has_many :shopping_cart_items, dependent: :destroy
  has_many :cart_session_imports, dependent: :restrict_with_error

  validates :status, inclusion: { in: STATUSES }
  validates :last_activity_at, presence: true

  validate :active_cart_has_no_terminal_fields
  validate :converted_cart_requirements
  validate :merged_cart_requirements
  validate :cleared_cart_requirements
  validate :merged_into_cart_not_self
  validate :terminal_cart_has_no_anonymous_token

  private

  def active_cart_has_no_terminal_fields
    return unless status == 'active'

    errors.add(:sale_order_id, 'must be blank for an active cart') if sale_order_id.present?
    errors.add(:converted_at, 'must be blank for an active cart') if converted_at.present?
    errors.add(:closed_at, 'must be blank for an active cart') if closed_at.present?
    errors.add(:merged_into_cart_id, 'must be blank for an active cart') if merged_into_cart_id.present?
  end

  def converted_cart_requirements
    return unless status == 'converted'

    errors.add(:sale_order_id, "can't be blank for a converted cart") if sale_order_id.blank?
    errors.add(:converted_at, "can't be blank for a converted cart") if converted_at.blank?
    errors.add(:closed_at, "can't be blank for a converted cart") if closed_at.blank?
  end

  def merged_cart_requirements
    return unless status == 'merged'

    errors.add(:merged_into_cart_id, "can't be blank for a merged cart") if merged_into_cart_id.blank?
    errors.add(:closed_at, "can't be blank for a merged cart") if closed_at.blank?
  end

  def cleared_cart_requirements
    return unless status == 'cleared'

    errors.add(:closed_at, "can't be blank for a cleared cart") if closed_at.blank?
  end

  def merged_into_cart_not_self
    return if merged_into_cart_id.blank? || id.blank?

    errors.add(:merged_into_cart_id, 'cannot merge a cart into itself') if merged_into_cart_id == id
  end

  # Once a cart reaches any terminal status, its anonymous claim capability is
  # done - a converted/merged/cleared cart can no longer be claimed via token.
  def terminal_cart_has_no_anonymous_token
    return if status == 'active'
    return if anonymous_token_digest.blank?

    errors.add(:anonymous_token_digest, 'must be cleared once a cart reaches a terminal status')
  end
end
