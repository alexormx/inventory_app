module Admin
	class SaleOrdersAuditsController < ApplicationController
		before_action :authorize_admin!

		def index
			render plain: "Sale orders audit dashboard pending implementation", status: :ok
		end

		def fix_gaps
			redirect_to admin_sale_orders_audit_path, notice: "Fix gaps job en cola (placeholder)."
		end
	end
end

