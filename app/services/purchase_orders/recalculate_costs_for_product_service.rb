module PurchaseOrders
	# Servicio para recalcular costos derivados de las líneas de purchase orders
	# asociado a un producto específico. Se invoca desde callbacks del modelo
	# `Product` cuando cambian dimensiones/peso u otros factores que puedan
	# impactar costos logísticos o de composición.
	#
	# Contrato:
	#   input : product (Product)
	#   call  : retorna Result (Struct) con totales y si hubo cambios
	#   efectos: actualiza columnas alpha_cost / compose_cost en PurchaseOrderItem
	#            si existen y si el cálculo provisional difiere.
	class RecalculateCostsForProductService
		Result = Struct.new(
			:product_id,
			:items_scanned,
			:items_updated,
			:errors,
			keyword_init: true
		)

		def initialize(product)
			@product = product
		end

		def call
			return empty_result("nil product") unless @product
			return empty_result("no id") unless @product.id

			scope = if defined?(PurchaseOrderItem)
				PurchaseOrderItem.where(product_id: @product.id)
			else
				PurchaseOrderItem.none
			end

			items_scanned = 0
			items_updated = 0
			errors = []

			scope.find_in_batches(batch_size: 200) do |batch|
				batch.each do |item|
					items_scanned += 1
					begin
						attrs = recompute_costs_for(item)
						next if attrs.empty?
						item.update_columns(attrs)
						items_updated += 1
					rescue => e
						Rails.logger.error("[RecalculateCostsForProductService] item=#{item.id} error=#{e.class} #{e.message}")
						errors << "item #{item.id}: #{e.class}: #{e.message}"
					end
				end
			end

			Result.new(
				product_id: @product.id,
				items_scanned: items_scanned,
				items_updated: items_updated,
				errors: errors
			)
		end

		private

		# Reusa la misma heurística provisional que el job masivo:
		# alpha_cost = quantity * unit_cost
		# compose_cost = alpha_cost * 1.05
		def recompute_costs_for(item)
			return {} unless item.respond_to?(:quantity) && item.respond_to?(:unit_cost)
			return {} unless item.respond_to?(:alpha_cost) && item.respond_to?(:compose_cost)

			qty = item.quantity.to_f
			unit = item.unit_cost.to_f
			new_alpha = (qty * unit).round(2)
			new_compose = (new_alpha * 1.05).round(2)
			changes = {}
			changes[:alpha_cost] = new_alpha if item.alpha_cost.to_f != new_alpha
			changes[:compose_cost] = new_compose if item.compose_cost.to_f != new_compose
			changes
		end

		def empty_result(error_msg = nil)
			Result.new(
				product_id: @product&.id,
				items_scanned: 0,
				items_updated: 0,
				errors: error_msg ? [error_msg] : []
			)
		end
	end
end

