class ShippingAddress < ApplicationRecord
  belongs_to :user

  validates :full_name, :line1, :city, :postal_code, :country, presence: true
  validates :postal_code, format: { with: /\A\d{5}\z/, message: 'CP inválido' }, allow_blank: true

  before_save :ensure_single_default
  before_validation :normalize_location_fields

  scope :ordered, -> { order(default: :desc, created_at: :asc) }

  def to_one_line
    [line1, line2, city, state, postal_code, country].reject(&:blank?).join(', ')
  end

  private
  def ensure_single_default
    return unless default? && user_id.present?
    ShippingAddress.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end

  def normalize_location_fields
    %i[settlement municipality state].each do |attr|
      val = self[attr]
      next if val.nil?
      stripped = val.to_s.strip
      self[attr] = stripped.blank? || stripped.downcase == 'nan' ? nil : stripped.downcase
    end
    if postal_code.present?
      self.postal_code = postal_code.to_s.gsub(/[^0-9]/,'')[0,5]
    end
  end
end
