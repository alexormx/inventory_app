module Admin
	class InventoryAuditsController < ApplicationController
		before_action :authorize_admin!

		def index
			# Render vista con acciones de reconciliación
		end

		def fix_inconsistencies
			# Placeholder: implementar lógica de corrección posteriormente
			redirect_to admin_inventory_audit_path, notice: "Fix inconsistencies job en cola (placeholder)."
		end

		def fix_missing_so_lines
			redirect_to admin_inventory_audit_path, notice: "Fix missing sale order lines en cola (placeholder)."
		end
	end
end

