# frozen_string_literal: true

module ProductsHelper
  # Muestra la cantidad de stock limitada para el frontend público
  # Si hay más de 10 unidades, muestra ">10" para no revelar stock real
  MAX_DISPLAY_STOCK = 10

  def display_stock_count(count)
    return '0' if count.nil? || count <= 0

    count > MAX_DISPLAY_STOCK ? '>10' : count.to_s
  end

  # Etiqueta de disponibilidad por piezas para el frontend público.
  # Crea urgencia en stock bajo sin revelar el inventario exacto: a partir de
  # 5 unidades solo se muestra ">5 piezas".
  def stock_pieces_label(count)
    count = count.to_i
    case count
    when ..0 then nil
    when 1 then 'Última pieza'
    when 2 then 'Últimas 2 piezas'
    when 3 then 'Últimas 3 piezas'
    when 4 then '4 piezas'
    else '>5 piezas'
    end
  end

  # Presentación de cada distintivo comercial para el catálogo web. La lógica de
  # cuál evento aplica vive en Product#catalog_event (fuente única, compartida con
  # el catálogo PDF/imagen); aquí solo mapeamos el símbolo a etiqueta/estilo.
  CATALOG_EVENT_PRESENTATION = {
    new:        { label: 'Nuevo en catálogo', icon: 'fa-wand-magic-sparkles', css: 'badge-new',
                  title: 'Nuevo en catálogo · publicado recientemente por primera vez' },
    reappeared: { label: 'De vuelta en catálogo', icon: 'fa-rotate-left', css: 'badge-reappeared',
                  title: 'De vuelta en catálogo · vuelve a estar disponible tras una pausa' },
    restocked:  { label: 'Recién resurtido', icon: 'fa-boxes-stacked', css: 'badge-restocked',
                  title: 'Recién resurtido · volvió a haber piezas disponibles' }
  }.freeze

  # Resuelve el distintivo comercial de mayor prioridad para un producto.
  # Prioridad: Nuevo en catálogo > De vuelta en catálogo > Recién resurtido.
  # Devuelve un Hash con :type, :label, :icon, :css, :title o nil si no aplica.
  def catalog_event_for(product, now: Time.current)
    type = product.catalog_event(now: now)
    return unless type

    CATALOG_EVENT_PRESENTATION[type].merge(type: type)
  end

  # Badge comercial (independiente de disponibilidad). Fuente única del texto y
  # estilo; devuelve nil si ningún evento está dentro de su ventana.
  def catalog_event_badge(product)
    event = catalog_event_for(product)
    return unless event

    icon = content_tag(:i, '', class: "fas #{event[:icon]} me-1", 'aria-hidden': 'true')
    content_tag :span, safe_join([icon, event[:label]]),
                class: "badge #{event[:css]}",
                title: event[:title]
  end

  # Genera un badge unificado de disponibilidad (En stock / Preorden / Sobre pedido / Fuera de stock)
  # compact_eta: en la tarjeta del catálogo muestra la fecha corta sin año
  # ("Llega aprox. 6 ago."); el tooltip conserva la fecha completa.
  def stock_badge(product, quantity: nil, suppress_pending_note: false, on_hand_override: nil, in_transit_eta_override: :unset, compact_eta: false)
    on_hand = on_hand_override.nil? ? product.current_on_hand : on_hand_override
    pending_split = quantity ? product.split_immediate_and_pending(quantity) : nil
    base_classes = 'badge rounded-pill fw-normal'
    preorder_eta = SiteSetting.get('preorder_eta_days', 60).to_i
    backorder_eta = SiteSetting.get('backorder_eta_days', 60).to_i
    in_transit_eta = in_transit_eta_override == :unset ? earliest_in_transit_eta(product) : in_transit_eta_override

    label, classes, tooltip = if on_hand.positive?
                                ['En stock', 'bg-success', 'Disponible para envío inmediato']
                              elsif in_transit_eta.present?
                                full_fmt = spanish_short_date(in_transit_eta)
                                label_txt = compact_eta ? "Llega aprox. #{spanish_compact_date(in_transit_eta)}" : "Llega ~#{full_fmt}"
                                [label_txt, 'badge-incoming', "En tránsito desde proveedor · Llegada estimada #{full_fmt}"]
                              elsif product.preorder_available
                                if product.respond_to?(:launch_date) && product.launch_date.present?
                                  estimated_date = begin
                                    (product.launch_date + preorder_eta.days)
                                  rescue StandardError
                                    nil
                                  end
                                  if estimated_date
                                    launch_fmt = spanish_short_date(product.launch_date)
                                    eta_fmt = spanish_short_date(estimated_date)
                                    tip = "Lanzamiento: #{launch_fmt} · Disponible aprox el #{eta_fmt}"
                                  else
                                    tip = "Lanzamiento registrado · Disponible aproximadamente en #{preorder_eta} días"
                                  end
                                else
                                  tip = 'Sin fecha de lanzamiento confirmada · Disponible en ~90 días después de confirmar'
                                end
                                ['Preventa', 'bg-warning text-dark', tip]
                              elsif product.backorder_allowed
                                ['Sobre pedido', 'bg-info text-dark', "Se solicitará al proveedor. Disponible aprox en #{backorder_eta} días tras confirmar"]
                              else
                                ['Fuera de stock', 'bg-secondary', 'No disponible actualmente']
                              end

    pending_note = if !suppress_pending_note && pending_split && pending_split[:pending].positive? && pending_split[:pending_type]
                     " (#{pending_split[:pending]} pend.)"
                   end

    content_tag :span, label + (pending_note || ''), class: [base_classes, classes].join(' '), title: tooltip, data: { bs_toggle: 'tooltip' }
  end

  def stock_eta(product, in_transit_eta_override: :unset)
    on_hand = product.current_on_hand
    return nil if on_hand.positive?

    in_transit_eta = in_transit_eta_override == :unset ? earliest_in_transit_eta(product) : in_transit_eta_override
    return "Llegada estimada: #{spanish_short_date(in_transit_eta)}" if in_transit_eta.present?

    preorder_eta = SiteSetting.get('preorder_eta_days', 60).to_i
    backorder_eta = SiteSetting.get('backorder_eta_days', 60).to_i
    if product.preorder_available
      return 'Disponible en ~90 días' unless product.respond_to?(:launch_date) && product.launch_date.present?

      estimated_date = begin
        (product.launch_date + preorder_eta.days)
      rescue StandardError
        nil
      end
      return "Disponible aprox el #{spanish_short_date(estimated_date)}" if estimated_date

      return "Disponible en ~#{preorder_eta} días"

    elsif product.backorder_allowed
      return "Disponible en ~#{backorder_eta} días"
    end
    nil
  end

  # Devuelve la fecha estimada de llegada más próxima de inventario en tránsito,
  # o nil si no hay piezas en camino. Solo se usa como fallback cuando el caller
  # no precomputó la fecha (ej. en la vista de detalle); en la grilla del catálogo
  # el controller pasa el override para evitar N+1.
  def earliest_in_transit_eta(product)
    return nil unless product.respond_to?(:inventories)

    product.inventories.in_transit
           .joins(:purchase_order)
           .where.not(purchase_orders: { expected_delivery_date: nil })
           .where('purchase_orders.expected_delivery_date >= ?', Date.current)
           .minimum('purchase_orders.expected_delivery_date')
  end

  # Helper para imágenes estáticas en `<picture>`
  def responsive_asset_image(filename, alt:, widths: [480, 768, 1200], css_class: '', loading: 'lazy', aspect_ratio: nil, fetch_priority: nil)
    return '' if filename.blank?

    base_name = filename.sub(/\.[^.]+$/, '')
    orig_ext  = File.extname(filename).delete('.')
    asset_exists = asset_exists?(filename)
    unless asset_exists
      placeholder = 'placeholder.png'
      return image_tag(placeholder, alt: alt, class: css_class) unless asset_exists?(placeholder)

      filename = placeholder
      base_name = placeholder.sub(/\.[^.]+$/, '')
      orig_ext = 'png'
    end
    widths = Array(widths).map(&:to_i).select(&:positive?).uniq.sort
    widths = [480, 768, 1200] if widths.empty?
    sizes_attr = "(max-width: #{widths.max}px) 100vw, #{widths.max}px"
    variant_finder = lambda do |fmt, w|
      name = "#{base_name}-#{w}w.#{fmt}"
      asset_exists?(name) ? name : nil
    end
    sources = []
    %w[avif webp].each do |fmt|
      entries = widths.map do |w|
        vf = variant_finder.call(fmt, w)
        vf && "#{asset_path(vf)} #{w}w"
      end.compact
      next if entries.empty?

      sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: entries.join(', '), sizes: sizes_attr)
    end
    # Fallback srcset (original format) usando variantes pre-generadas si existen
    fallback_entries = widths.map do |w|
      vf = variant_finder.call(orig_ext, w)
      vf && "#{asset_path(vf)} #{w}w"
    end.compact
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
        if w.positive? && h.positive?
          img_options[:width]  = widths.max
          img_options[:height] = (widths.max * (h / w)).round
        end
      elsif aspect_ratio.to_f.positive?
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
    Rails.application.assets&.find_asset(logical_path) || (Rails.application.config.assets.compile == false && Rails.application.assets_manifest.assets[logical_path])
  rescue StandardError
    false
  end

  # Helper para ActiveStorage
  def responsive_attachment_image(attachment, alt:, widths: [200, 400, 600], css_class: '', loading: 'lazy', square: true, fetch_priority: nil, id: nil, width: nil, height: nil, sizes: nil)
    return image_tag('placeholder.png', alt: alt, class: css_class) if attachment.blank?

    widths = Array(widths).map(&:to_i).select(&:positive?).uniq.sort
    widths = [200, 400, 600] if widths.empty?
    # Callers can pass a layout-accurate `sizes` so the browser picks the
    # smallest sufficient variant; without it we fall back to the conservative
    # full-width assumption (which over-fetches when the image renders small).
    sizes_attr = sizes.presence || "(max-width: #{widths.max}px) 100vw, #{widths.max}px"
    original_variants = {}
    widths.each do |w|
      resize_opt = square ? [w, w] : [w, nil]
      original_variants[w] = attachment.variant(resize_to_limit: resize_opt)
    rescue StandardError
    end
    sources = []
    %i[avif webp].each do |fmt|
      variant_urls = widths.map do |w|
        variant = attachment.variant(resize_to_limit: [w, w], format: fmt)
        [variant, w]
      rescue StandardError
        nil
      end.compact
      next if variant_urls.empty?

      srcset = variant_urls.map do |variant, w|
        url = url_for(variant)
        url = strip_locale_from_active_storage(url)
        "#{url} #{w}w"
      end.join(', ')
      sources << content_tag(:source, nil, type: "image/#{fmt}", srcset: srcset, sizes: sizes_attr)
    rescue StandardError
      next
    end
    largest_w = original_variants.keys.max
    fallback_variant = largest_w ? original_variants[largest_w] : attachment
    fallback_url = url_for(fallback_variant)
    fallback_url = strip_locale_from_active_storage(fallback_url)
    img_opts = { alt: alt, class: css_class, loading: loading, decoding: 'async', sizes: sizes_attr }
    img_opts[:id] = id if id
    img_opts[:fetchpriority] = fetch_priority if fetch_priority
    # Explicit intrinsic dimensions reserve layout space (reduces CLS). For
    # square product images this is the variant box; CSS object-fit keeps the
    # real aspect ratio without distortion.
    dim_w = width || (square ? widths.max : nil)
    dim_h = height || (square ? widths.max : nil)
    img_opts[:width] = dim_w if dim_w
    img_opts[:height] = dim_h if dim_h
    fallback_img = image_tag(fallback_url, **img_opts)
    content_tag(:picture, safe_join(sources) + fallback_img)
  end

  def spanish_short_date(date)
    return '' unless date

    months = %w[Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic]
    format('%02d-%s-%d', date.day, months[date.month - 1], date.year)
  end

  # Fecha compacta para tarjetas (móvil): día sin cero + mes abreviado en
  # minúscula, sin año. Ej.: "6 ago." La fecha completa se conserva en la
  # vista de detalle vía spanish_short_date.
  def spanish_compact_date(date)
    return '' unless date

    months = %w[ene feb mar abr may jun jul ago sep oct nov dic]
    "#{date.day} #{months[date.month - 1]}."
  end

  def strip_locale_from_active_storage(url)
    return url unless I18n.locale && I18n.locale != I18n.default_locale

    url.sub(%r{/#{I18n.locale}/rails/active_storage}, '/rails/active_storage')
  rescue StandardError
    url
  end

  # Costo pronosticado de restock: si el reorder_point es mayor que el stock actual
  # utiliza average_purchase_cost; fallback a last_purchase_cost; si no hay datos -> 0
  def predicted_restock_cost(product)
    on_hand = product.current_on_hand
    return 0 unless product.reorder_point.present? && product.reorder_point.to_i > on_hand

    pending_units = product.reorder_point.to_i - on_hand
    unit_cost = if product.average_purchase_cost.to_f.positive?
                  product.average_purchase_cost
                elsif product.last_purchase_cost.to_f.positive?
                  product.last_purchase_cost
                else
                  0
                end
    (pending_units * unit_cost.to_d).round(2)
  end

  # Devuelve la clase CSS para el badge de condición de inventario
  def condition_badge_class(condition)
    case condition.to_s
    when 'brand_new'
      'bg-primary'
    when 'misb', 'moc'
      'bg-success'
    when 'mib', 'mint'
      'bg-info'
    when 'loose'
      'bg-warning text-dark'
    when 'good', 'fair'
      'bg-secondary'
    else
      'bg-secondary'
    end
  end
end
