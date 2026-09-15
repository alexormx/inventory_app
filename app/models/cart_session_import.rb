# frozen_string_literal: true

# A crash-safe, exactly-once receipt for a legacy session-cart import: one
# row per browser-session import key, written first inside the import
# transaction by ShoppingCarts::SessionReconciler.
class CartSessionImport < ApplicationRecord
  belongs_to :shopping_cart

  validates :import_key_digest, presence: true, uniqueness: true
  validates :source_payload_digest, presence: true
end
