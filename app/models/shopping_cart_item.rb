# frozen_string_literal: true

class ShoppingCartItem < ApplicationRecord
  # Same canonical allowlist SaleOrderItem/InventoryAdjustmentLine already use
  # - not a new/renamed condition contract.
  ITEM_CONDITIONS = Inventory::ITEM_CONDITIONS

  belongs_to :shopping_cart
  belongs_to :product, optional: true

  enum :condition, ITEM_CONDITIONS, default: :brand_new

  validates :product_reference, presence: true
  validates :condition, presence: true
  # Match the database's technical storage bound, not the storefront's
  # per-condition purchase limits (which do not apply to historical carts).
  validates :quantity, presence: true,
                       numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000 }
  validates :product_reference, uniqueness: { scope: %i[shopping_cart_id condition] }
end
