class PostalCode < ApplicationRecord
  before_validation :normalize_fields

  validates :cp, presence: true, format: { with: /\A\d{5}\z/, message: 'CP inválido' }
  validates :state, :municipality, :settlement, presence: true

  scope :by_cp, ->(cp_value) { where(cp: cp_value.to_s.strip) }

  private
  def normalize_fields
    %i[cp state municipality settlement settlement_type].each do |attr|
      val = self[attr]
      val = nil if val.is_a?(String) && val.strip.downcase.in?(['', 'nan'])
      self[attr] = val.is_a?(String) ? val.strip.downcase : val
    end
    self.cp = cp&.gsub(/[^0-9]/, '') if cp.present?
  end
end
