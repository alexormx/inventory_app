# frozen_string_literal: true

module ShippingAddressesHelper
  MEXICAN_STATES = [
    'Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche', 'Chiapas', 'Chihuahua',
    'Ciudad de México', 'Coahuila', 'Colima', 'Durango', 'Estado de México', 'Guanajuato', 'Guerrero',
    'Hidalgo', 'Jalisco', 'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca', 'Puebla', 'Querétaro',
    'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora', 'Tabasco', 'Tamaulipas', 'Tlaxcala', 'Veracruz',
    'Yucatán', 'Zacatecas'
  ].freeze

  # Conserva un valor guardado a mano antes de que existiera la lista, para no perderlo al editar.
  def address_state_options(current)
    current.present? && MEXICAN_STATES.exclude?(current) ? MEXICAN_STATES + [current] : MEXICAN_STATES
  end

  def address_country_options(current)
    options = [%w[México MX]]
    current.present? && current != 'MX' ? options + [[current, current]] : options
  end
end
