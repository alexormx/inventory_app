# frozen_string_literal: true

class PostalCode < ApplicationRecord
  # Validaciones básicas según el schema
  validates :cp, presence: true, length: { is: 5 }
  validates :state, :municipality, :settlement, presence: true

  # Normalización sencilla antes de validar
  before_validation :strip_values

  scope :by_cp, ->(cp) { where(cp: cp.to_s.strip.first(5)) }
  scope :ordered, -> { order(cp: :asc, settlement: :asc) }

  def self.lookup(cp)
    by_cp(cp).ordered
  end

  private

  def strip_values
    self.cp = cp.to_s.strip
    self.state = state.to_s.strip
    self.municipality = municipality.to_s.strip
    self.settlement = settlement.to_s.strip
    self.settlement_type = settlement_type.to_s.strip if settlement_type
  end
end

