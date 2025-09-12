class ShippingAddress < ApplicationRecord
	belongs_to :user

	# Validaciones
	validates :full_name, :line1, :city, :postal_code, :country, presence: true
	validates :label, presence: true
	validates :postal_code, length: { in: 4..10 }

	before_validation :normalize_fields
	before_save :ensure_single_default

	scope :ordered, -> { order(default: :desc, created_at: :asc) }

	private

	def normalize_fields
		self.label = label.to_s.strip.presence || "Principal"
		self.full_name = full_name.to_s.strip
		self.line1 = line1.to_s.strip
		self.line2 = line2.to_s.strip if line2
		self.city = city.to_s.strip
		self.state = state.to_s.strip if state
		self.postal_code = postal_code.to_s.strip
		self.country = country.to_s.strip.upcase.presence || "MX"
	end

	def ensure_single_default
		return unless default_changed? && default
		# Desmarcar otras direcciones del mismo usuario (evitar callbacks recursivos usando update_all)
		self.class.where(user_id: user_id, default: true).where.not(id: id).update_all(default: false)
	end
end

