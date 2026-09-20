# frozen_string_literal: true

# Temporary ownership of ONE exact physical Inventory row by a durable
# ShoppingCart.
#
# A hold is deliberately NOT an inventory status: physical inventory state
# (available / in_transit / reserved / sold) stays untouched, and cart
# ownership lives here alongside it. That keeps the admin and allocator views
# of physical stock exactly as they were.
#
# Exclusivity is a database guarantee, not a Ruby check: `inventory_id` carries
# a UNIQUE index, so at most one hold row can ever reference a physical unit.
# Claims go through Carts::HoldInventory, which resolves competition with a
# single atomic INSERT ... ON CONFLICT DO UPDATE.
#
# Expiry is authoritative from `expires_at`, evaluated against DATABASE time.
# An expired hold is logically inactive the instant it passes, whether or not
# the cleanup job has deleted its row - correctness never waits on cleanup.
class CartInventoryHold < ApplicationRecord
  HOLD_DURATION = 4.hours

  belongs_to :shopping_cart
  belongs_to :inventory
  belongs_to :shopping_cart_item, optional: true

  validates :expires_at, presence: true

  # Database time, not Time.current: ownership is decided by the same clock
  # that runs the atomic claim, so Ruby/Postgres clock skew can never make a
  # row look held to one path and free to another.
  #
  # clock_timestamp() rather than CURRENT_TIMESTAMP on purpose: CURRENT_TIMESTAMP
  # is frozen at transaction start, so a hold that expires *during* a long
  # checkout transaction would still read as active. clock_timestamp() advances,
  # so the expiry boundary is real wall-clock time everywhere it is judged.
  scope :active,  -> { where('cart_inventory_holds.expires_at > clock_timestamp()') }
  scope :expired, -> { where('cart_inventory_holds.expires_at <= clock_timestamp()') }
  scope :for_cart, ->(cart) { where(shopping_cart_id: cart) }
  scope :for_cart_item, ->(item) { where(shopping_cart_item_id: item) }

  def active?
    expires_at.present? && expires_at > Time.current
  end

  def expired?
    !active?
  end
end
