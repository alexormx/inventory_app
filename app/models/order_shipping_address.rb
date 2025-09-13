class OrderShippingAddress < ApplicationRecord
  belongs_to :sale_order
  # FK opcional a la dirección fuente
  belongs_to :source_shipping_address, class_name: 'ShippingAddress', optional: true

  validates :full_name, :line1, :city, :postal_code, :country, :shipping_method, presence: true

  # Formato compacto reutilizable
  def to_one_line
    parts = [line1]
    parts << line2 if line2.present?
    loc = [city, state].compact.reject(&:blank?).join(', ')
    parts << loc unless loc.blank?
    parts << postal_code
    parts << country
    parts.compact.reject(&:blank?).join(' | ')
  end

  def as_json_snapshot
    attributes.slice('full_name','line1','line2','city','state','postal_code','country','shipping_method')
  end
end
