module ProductsHelper
	# Genera un badge unificado de disponibilidad (En stock / Preorden / Sobre pedido / Fuera de stock)
	def stock_badge(product, quantity: nil, suppress_pending_note: false)
		on_hand = product.current_on_hand
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
			["Preventa", "bg-warning text-dark", tip]
		elsif product.backorder_allowed
			["Sobre pedido", "bg-info text-dark", "Se solicitará al proveedor. Disponible aprox en #{backorder_eta} días tras confirmar"]
		else
			["Fuera de stock", "bg-secondary", "No disponible actualmente"]
		end

		pending_note = if !suppress_pending_note && pending_split && pending_split[:pending].positive? && pending_split[:pending_type]
			" (#{pending_split[:pending]} pend.)"
		end

		content_tag :span, label + (pending_note || ''), class: [base_classes, classes].join(' '), title: tooltip, data: { bs_toggle: 'tooltip' }
	end

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

	# Helper para imágenes estáticas en `<picture>`
	def responsive_asset_image(filename, alt:, widths: [480,768,1200], css_class: "", loading: 'lazy', aspect_ratio: nil, fetch_priority: nil)
		return '' if filename.blank?
		base_name = filename.sub(/\.[^.]+$/,'')
		asset_exists = Rails.application.assets&.find_asset(filename) || (Rails.application.config.assets.compile == false && Rails.application.assets_manifest.assets[filename]) rescue false
		unless asset_exists
			filename = 'placeholder.png' if Rails.application.assets&.find_asset('placeholder.png') || (Rails.application.config.assets.compile == false && Rails.application.assets_manifest.assets['placeholder.png']) rescue false
		end
		widths = Array(widths).map(&:to_i).select { |w| w > 0 }.uniq.sort
		widths = [480, 768, 1200] if widths.empty?
		sizes_attr = "(max-width: #{widths.max}px) 100vw, #{widths.max}px"
		sources = []
		%w[avif webp].each do |fmt|
			candidate_name = "#{base_name}.#{fmt}"
			candidate_exists = Rails.application.assets&.find_asset(candidate_name) || (Rails.application.config.assets.compile == false && Rails.application.assets_manifest.assets[candidate_name]) rescue false
			next unless candidate_exists
			path = asset_path(candidate_name)
			srcset = widths.map { |w| "#{path}?w=#{w} #{w}w" }.join(', ')
			sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: srcset, sizes: sizes_attr)
		end
		img_options = { alt: alt, class: css_class, loading: loading, decoding: 'async', sizes: sizes_attr }
		img_options[:fetchpriority] = fetch_priority if fetch_priority
		if aspect_ratio
			if aspect_ratio.is_a?(String) && aspect_ratio.include?(':')
				w, h = aspect_ratio.split(':').map(&:to_f)
				if w > 0 && h > 0
					img_options[:width]  = widths.max
					img_options[:height] = (widths.max * (h / w)).round
				end
			elsif aspect_ratio.to_f > 0
				img_options[:width]  = widths.max
				img_options[:height] = (widths.max / aspect_ratio.to_f).round
			end
		end
		fallback_img = image_tag(filename, **img_options)
		picture = content_tag(:picture, safe_join(sources) + fallback_img)
		noscript_fallback = content_tag(:noscript) { image_tag(filename, alt: alt, class: css_class) }
		picture + noscript_fallback
	end

	# Helper para ActiveStorage
	def responsive_attachment_image(attachment, alt:, widths: [200,400,600], css_class: "", loading: 'lazy', square: true, fetch_priority: nil)
		# ActiveStorage::Attachment (individual) no implementa attached?; sólo los proxies.
		return image_tag('placeholder.png', alt: alt, class: css_class) unless attachment.present?
		widths = Array(widths).map(&:to_i).select { |w| w > 0 }.uniq.sort
		widths = [200, 400, 600] if widths.empty?
		sizes_attr = "(max-width: #{widths.max}px) 100vw, #{widths.max}px"
		original_variants = {}
		widths.each do |w|
			begin
				resize_opt = square ? [w, w] : [w, nil]
				original_variants[w] = attachment.variant(resize_to_limit: resize_opt)
			rescue
			end
		end
		sources = []
		%i[avif webp].each do |fmt|
			begin
				variant_urls = widths.map do |w|
					variant = attachment.variant(resize_to_limit: [w, w], format: fmt)
					[variant, w]
				rescue
					nil
				end.compact
				next if variant_urls.empty?
				srcset = variant_urls.map { |variant, w| "#{url_for(variant)} #{w}w" }.join(', ')
				sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: srcset, sizes: sizes_attr)
			rescue
				next
			end
		end
		largest_w = original_variants.keys.max
		fallback_variant = largest_w ? original_variants[largest_w] : attachment
		img_opts = { alt: alt, class: css_class, loading: loading, decoding: 'async', sizes: sizes_attr }
		img_opts[:fetchpriority] = fetch_priority if fetch_priority
		fallback_img = image_tag(url_for(fallback_variant), **img_opts)
		content_tag(:picture, safe_join(sources) + fallback_img)
	end

	def spanish_short_date(date)
		return '' unless date
		months = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic]
		"%02d-%s-%d" % [date.day, months[date.month-1], date.year]
	end
end
