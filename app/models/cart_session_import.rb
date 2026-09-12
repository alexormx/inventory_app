# frozen_string_literal: true

# A crash-safe, exactly-once receipt for a future legacy session-cart import
# (PR B). This PR only defines the model/table; nothing writes to it yet.
class CartSessionImport < ApplicationRecord
  belongs_to :shopping_cart

  validates :import_key_digest, presence: true, uniqueness: true
  validates :source_payload_digest, presence: true
end
