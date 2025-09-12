class AddDirectionToInventoryAdjustmentLines < ActiveRecord::Migration[8.0]
	def up
		return unless table_exists?(:inventory_adjustment_lines)

		unless column_exists?(:inventory_adjustment_lines, :direction)
			add_column :inventory_adjustment_lines, :direction, :string, null: false, default: "increase"
		end

		unless index_exists?(:inventory_adjustment_lines, :direction)
			add_index :inventory_adjustment_lines, :direction
		end
	end

	def down
		return unless table_exists?(:inventory_adjustment_lines)

		if index_exists?(:inventory_adjustment_lines, :direction)
			remove_index :inventory_adjustment_lines, :direction
		end
		if column_exists?(:inventory_adjustment_lines, :direction)
			remove_column :inventory_adjustment_lines, :direction
		end
	end
end

