module ProductsHelper
	# Genera un badge unificado de disponibilidad (En stock / Preorden / Sobre pedido / Fuera de stock)
	def stock_badge(product, quantity: nil, suppress_pending_note: false, on_hand_override: nil)
		on_hand = on_hand_override.nil? ? product.current_on_hand : on_hand_override
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
		original = filename
		base_name = filename.sub(/\.[^.]+$/,'')
		orig_ext  = File.extname(filename).delete('.')
		asset_exists = asset_exists?(filename)
		unless asset_exists
			placeholder = 'placeholder.png'
			return image_tag(placeholder, alt: alt, class: css_class) unless asset_exists?(placeholder)
			filename = placeholder
			base_name = placeholder.sub(/\.[^.]+$/,'')
			orig_ext = 'png'
		end
		widths = Array(widths).map(&:to_i).select { |w| w > 0 }.uniq.sort
		widths = [480, 768, 1200] if widths.empty?
		sizes_attr = "(max-width: #{widths.max}px) 100vw, #{widths.max}px"
		variant_finder = ->(fmt, w) do
			name = "#{base_name}-#{w}w.#{fmt}"
			asset_exists?(name) ? name : nil
		end
		sources = []
		%w[avif webp].each do |fmt|
			entries = widths.map { |w| vf = variant_finder.call(fmt, w); vf && "#{asset_path(vf)} #{w}w" }.compact
			next if entries.empty?
			sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: entries.join(', '), sizes: sizes_attr)
		end
		# Fallback srcset (original format) usando variantes pre-generadas si existen
		fallback_entries = widths.map { |w| vf = variant_finder.call(orig_ext, w); vf && "#{asset_path(vf)} #{w}w" }.compact
		fallback_src = if fallback_entries.any?
			{ srcset: fallback_entries.join(', '), sizes: sizes_attr }
		else
			{ src: asset_path(filename) }
		end
		img_options = { alt: alt, class: css_class, loading: loading, decoding: 'async' }.merge(fallback_src)
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
		fallback_img = image_tag(fallback_entries.any? ? fallback_entries.last.split.first : filename, **img_options)
		picture = content_tag(:picture, safe_join(sources) + fallback_img)
		noscript_fallback = content_tag(:noscript) { image_tag(filename, alt: alt, class: css_class) }
		picture + noscript_fallback
	end

	private

	def asset_exists?(logical_path)
		Rails.application.assets&.find_asset(logical_path) || (Rails.application.config.assets.compile == false && Rails.application.assets_manifest.assets[logical_path]) rescue false
	end

	# Helper para ActiveStorage
	def responsive_attachment_image(attachment, alt:, widths: [200,400,600], css_class: "", loading: 'lazy', square: true, fetch_priority: nil, id: nil)
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
				srcset = variant_urls.map do |variant, w|
					url = url_for(variant)
					url = strip_locale_from_active_storage(url)
					"#{url} #{w}w"
				end.join(', ')
				sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: srcset, sizes: sizes_attr)
			rescue
				next
			end
		end
		largest_w = original_variants.keys.max
		fallback_variant = largest_w ? original_variants[largest_w] : attachment
		fallback_url = url_for(fallback_variant)
		fallback_url = strip_locale_from_active_storage(fallback_url)
		img_opts = { alt: alt, class: css_class, loading: loading, decoding: 'async', sizes: sizes_attr }
		img_opts[:id] = id if id
		img_opts[:fetchpriority] = fetch_priority if fetch_priority
		fallback_img = image_tag(fallback_url, **img_opts)
		content_tag(:picture, safe_join(sources) + fallback_img)
	end

	def spanish_short_date(date)
		return '' unless date
		months = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic]
		"%02d-%s-%d" % [date.day, months[date.month-1], date.year]
	end

	def strip_locale_from_active_storage(url)
		return url unless I18n.locale && I18n.locale != I18n.default_locale
		url.sub(%r{/#{I18n.locale}/rails/active_storage}, '/rails/active_storage')
	rescue
		url
	end
end
