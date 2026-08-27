# frozen_string_literal: true

# Una línea del borrador: producto + cuántas piezas piensa dejar el operador en
# el estante. No reserva nada; la verdad está en inventories.
class LocationAssignmentDraftLine < ApplicationRecord
  belongs_to :location_assignment_draft, inverse_of: :lines
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
