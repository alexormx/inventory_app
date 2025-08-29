module ProductsHelper
	# Genera un badge unificado de disponibilidad (En stock / Preorden / Sobre pedido / Fuera de stock)
	# Opciones:
	#   quantity: para contextos de carrito, decidir si ya alcanzó stock
	def stock_badge(product, quantity: nil)
		on_hand = product.current_on_hand
		oversell = product.oversell_allowed?
		pending_split = quantity ? product.split_immediate_and_pending(quantity) : nil
		base_classes = "badge rounded-pill fw-normal"

			preorder_eta = SiteSetting.get('preorder_eta_days', 60).to_i
			backorder_eta = SiteSetting.get('backorder_eta_days', 60).to_i

				label, classes, tooltip = if on_hand > 0
					["En stock", "bg-success", "Disponible para envío inmediato"]
				elsif product.preorder_available
					if product.respond_to?(:launch_date) && product.launch_date.present?
						estimated_date = (product.launch_date + preorder_eta.days) rescue nil
						if estimated_date
							launch_fmt = spanish_short_date(product.launch_date)
							eta_fmt = spanish_short_date(estimated_date)
							tip = "Lanzamiento: #{launch_fmt} · Disponible aprox el #{eta_fmt}"
						else
							tip = "Lanzamiento registrado · Disponible aproximadamente en #{preorder_eta} días"
						end
					else
						tip = "Sin fecha de lanzamiento confirmada · Disponible en ~90 días después de confirmar"
					end
					["Preorden", "bg-warning text-dark", tip]
			elsif product.backorder_allowed
				["Sobre pedido", "bg-info text-dark", "Se solicitará al proveedor. Disponible aprox en #{backorder_eta} días tras confirmar"]
			else
				["Fuera de stock", "bg-secondary", "No disponible actualmente"]
			end

		pending_note = if pending_split && pending_split[:pending].positive? && pending_split[:pending_type]
			" (#{pending_split[:pending]} pend.)"
		end

		content_tag :span, label + (pending_note || ''), class: [base_classes, classes].join(' '), title: tooltip, data: { bs_toggle: 'tooltip' }
	end

		# Texto ETA visible bajo / junto al badge.
		def stock_eta(product)
			on_hand = product.current_on_hand
			return nil if on_hand > 0
			preorder_eta = SiteSetting.get('preorder_eta_days', 60).to_i
			backorder_eta = SiteSetting.get('backorder_eta_days', 60).to_i
			if product.preorder_available
				if product.respond_to?(:launch_date) && product.launch_date.present?
					estimated_date = (product.launch_date + preorder_eta.days) rescue nil
					return "Disponible aprox el #{spanish_short_date(estimated_date)}" if estimated_date
					return "Disponible en ~#{preorder_eta} días"
				else
					return "Disponible en ~90 días"
				end
			elsif product.backorder_allowed
				return "Disponible en ~#{backorder_eta} días"
			end
			nil
		end
end

# Formatea fecha como DD-MesAbrev-YYYY en español (e.g. 28-Ago-2025)
def spanish_short_date(date)
	return '' unless date
	months = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic]
	"#{date.day.to_s.rjust(2,'0')}-#{months[date.month-1]}-#{date.year}"
end
