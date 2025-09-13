class InventoryAdjuster
	Result = Struct.new(:success?, :adjusted, :errors, keyword_init: true)

	def initialize(user:, reason: nil)
		@user = user
		@reason = reason.to_s.strip.presence || "manual_adjustment"
		@errors = []
	end

	# adjustments: array de hashes { inventory_id:, delta: Integer, note: String }
	def call(adjustments)
		adjusted = 0
		ApplicationRecord.transaction do
			adjustments.each do |h|
				inv = Inventory.lock.find_by(id: h[:inventory_id])
				unless inv
					@errors << "Inventory #{h[:inventory_id]} no encontrado"
					next
				end
				delta = h[:delta].to_i
				next if delta == 0
				# Creamos un registro de ajuste de inventario (si existe el modelo InventoryAdjustmentLine/InventoryAdjustment)
				if defined?(InventoryAdjustment) && defined?(InventoryAdjustmentLine)
					adjustment = InventoryAdjustment.create!(performed_by_id: @user.id, reason: @reason, status: :applied)
					InventoryAdjustmentLine.create!(inventory_adjustment_id: adjustment.id, inventory_id: inv.id, delta: delta, direction: delta > 0 ? 'increase' : 'decrease')
				end
				# Aplicar delta directo al inventory (placeholder, idealmente se usaría un servicio con validaciones de negocio)
				new_qty = inv.quantity.to_i + delta
				if new_qty < 0
					@errors << "Inventory #{inv.id} quedaría negativo"
					raise ActiveRecord::Rollback
				end
				inv.update_columns(quantity: new_qty, updated_at: Time.current)
				adjusted += 1
			end
			raise ActiveRecord::Rollback if @errors.any?
		end
		Result.new(success?: @errors.empty?, adjusted: adjusted, errors: @errors)
	rescue => e
		@errors << "Exception: #{e.class} #{e.message}"
		Result.new(success?: false, adjusted: 0, errors: @errors)
	end
end

