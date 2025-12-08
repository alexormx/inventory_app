# frozen_string_literal: true

class OrderShippingAddress < ApplicationRecord
  belongs_to :sale_order
  # FK opcional a la dirección fuente
  belongs_to :source_shipping_address, class_name: 'ShippingAddress', optional: true

  validates :full_name, :line1, :city, :postal_code, :country, :shipping_method, presence: true

  # Formato compacto reutilizable
  def to_one_line
    parts = [line1]
    parts << line2 if line2.present?
    loc = [city, state].compact.compact_blank.join(', ')
    parts << loc if loc.present?
    parts << postal_code
    parts << country
    parts.compact.compact_blank.join(' | ')
  end

  def as_json_snapshot
    attributes.slice('full_name', 'line1', 'line2', 'city', 'state', 'postal_code', 'country', 'shipping_method')
  end
end
