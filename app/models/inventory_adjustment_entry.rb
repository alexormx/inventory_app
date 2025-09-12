class InventoryAdjustmentEntry < ApplicationRecord
	belongs_to :inventory_adjustment_line
	belongs_to :inventory

	ACTIONS = %w[created deleted status_changed marked_lost marked_damaged marked_scrap].freeze

	validates :action, presence: true, inclusion: { in: ACTIONS }
end
