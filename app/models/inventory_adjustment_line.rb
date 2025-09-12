class InventoryAdjustmentLine < ApplicationRecord
	# Associations
	belongs_to :inventory_adjustment
	belongs_to :product
	has_many :inventory_adjustment_entries, dependent: :destroy

	# Validations
	validates :product_id, :quantity, :direction, presence: true
	validates :quantity, numericality: { only_integer: true, greater_than: 0 }
	validates :direction, inclusion: { in: %w[increase decrease] }
		# Razones permitidas cuando es decrease (mapean a estados de inventario destino)
		ALLOWED_DECREASE_REASONS = %w[scrap marketing lost damaged].freeze

		validate :reason_allowed_for_decrease

	validate :immutable_when_parent_applied

	# Helpers
	def increase?
		direction == 'increase'
	end

	def decrease?
		direction == 'decrease'
	end

	private

	def immutable_when_parent_applied
		return if inventory_adjustment.blank? || inventory_adjustment.status_draft?
		errors.add(:base, 'No se puede modificar una línea mientras el ajuste está aplicado (reverse primero).') if changed?
	end

		def reason_allowed_for_decrease
			return unless decrease?
			if reason.blank? || !ALLOWED_DECREASE_REASONS.include?(reason)
				errors.add(:reason, "must be one of: #{ALLOWED_DECREASE_REASONS.join(', ')}")
			end
		end
end
