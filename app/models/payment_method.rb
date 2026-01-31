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

  # Genera instrucciones completas combinando datos de cuenta e instrucciones adicionales
  def full_instructions
    parts = []

    if account_number.present?
      parts << "#{bank_name.present? ? "Banco: #{bank_name}" : ''}"
      parts << "#{clabe_or_card_label}: #{account_number}"
      parts << "Beneficiario: #{account_holder}" if account_holder.present?
    end

    parts << instructions if instructions.present?
    parts.reject(&:blank?).join("\n")
  end

  # Determina si es CLABE (18 dígitos) o tarjeta
  def clabe_or_card_label
    return 'Número' unless account_number.present?

    digits_only = account_number.gsub(/\D/, '')
    digits_only.length == 18 ? 'CLABE' : 'Tarjeta/Cuenta'
  end

  private

  def normalize_code
    self.code = code.to_s.parameterize.underscore if code.present?
  end
end
