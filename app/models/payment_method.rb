# frozen_string_literal: true

class PaymentMethod < ApplicationRecord
  validates :name, presence: true
  validates :code, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  before_validation :normalize_code

  def self.for_select
    active.ordered.pluck(:name, :code)
  end

  # Para compatibilidad con el enum existente en Payment
  def self.legacy_enum_mapping
    {
      'tarjeta_de_credito' => 0,
      'efectivo' => 1,
      'transferencia_bancaria' => 2
    }
  end

  def legacy_enum_value
    self.class.legacy_enum_mapping[code]
  end

  private

  def normalize_code
    self.code = code.to_s.parameterize.underscore if code.present?
  end
end
