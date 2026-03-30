module SupplierCatalogItemsHelper
  def supplier_catalog_review_feed_label(feed)
    case feed.to_s
    when "recent_arrivals"
      "Arrivals HLJ"
    else
      "Agregados HLJ"
    end
  end

  def supplier_catalog_status_badge_class(status)
    case status.to_s
    when "in_stock", "low_stock"
      "bg-success"
    when "future_release", "backordered"
      "bg-primary"
    when "order_stop"
      "bg-warning text-dark"
    when "discontinued", "sold_out"
      "bg-secondary"
    else
      "bg-light text-dark"
    end
  end

  # Computes name similarity as the fraction of words from the shorter name
  # found in the longer name, with fuzzy substring matching for partial words.
  def name_similarity_score(a, b)
    words_a = tokenize_name(a)
    words_b = tokenize_name(b)
    return 0.0 if words_a.empty? || words_b.empty?

    # Use the shorter set as the reference to check containment
    shorter, longer = [words_a, words_b].sort_by(&:size)
    matches = shorter.count { |w| longer.include?(w) || longer.any? { |lw| fuzzy_match?(w, lw) } }
    matches.to_f / shorter.size
  end

  def similarity_badge(score)
    pct = (score * 100).round
    css = if score >= 0.6
            "text-success"
          elsif score >= 0.3
            "text-warning"
          else
            "text-danger"
          end
    content_tag(:span, "#{pct}%", class: "badge #{css} bg-opacity-10 #{css.sub('text-', 'bg-')}", title: "Similitud de nombres")
  end

  # Parse HLJ details_payload text dimensions to numeric values
  # item_size examples: "Approx. 150mm", "80mm×40mm×30mm", "L80 x W40 x H30 mm"
  # weight examples: "200g", "Approx. 150g"
  def parse_catalog_dimensions(details_payload)
    result = { weight_gr: nil, length_cm: nil, width_cm: nil, height_cm: nil }
    return result if details_payload.blank?

    # Parse weight
    weight_text = details_payload["weight"].to_s
    if weight_text.present?
      weight_match = weight_text.match(/(\d+(?:\.\d+)?)\s*g/i)
      result[:weight_gr] = weight_match[1].to_f if weight_match
    end

    # Parse dimensions from item_size
    size_text = details_payload["item_size"].to_s
    if size_text.present?
      # Try to find multiple dimensions: "80mm×40mm×30mm" or "80 x 40 x 30 mm"
      dims = size_text.scan(/(\d+(?:\.\d+)?)\s*(?:mm|cm)?/).flatten.map(&:to_f)
      unit_is_cm = size_text.match?(/\bcm\b/i)
      if dims.size >= 3
        dims = dims.first(3).sort.reverse # L, W, H descending
        if unit_is_cm
          result[:length_cm] = dims[0]
          result[:width_cm]  = dims[1]
          result[:height_cm] = dims[2]
        else
          # assume mm, convert to cm
          result[:length_cm] = (dims[0] / 10.0).round(1)
          result[:width_cm]  = (dims[1] / 10.0).round(1)
          result[:height_cm] = (dims[2] / 10.0).round(1)
        end
      elsif dims.size == 1
        # Single dimension (e.g. "Approx. 150mm") → use as length
        val = unit_is_cm ? dims[0] : (dims[0] / 10.0).round(1)
        result[:length_cm] = val
      end
    end

    result
  end

  private

  def tokenize_name(name)
    text = name.to_s.downcase
    # Remove scale patterns like "1/57", "1/62"
    text = text.gsub(/\b1\/\d+\b/, "")
    # Remove "No." or "No " prefix before numbers (Tomica numbering)
    text = text.gsub(/\bno\.?\s*(?=\d)/, "")
    # Keep only alphanumeric and spaces
    text = text.gsub(/[^a-z0-9\s]/, " ")
    # Split, normalize numbers (strip leading zeros), filter short words
    text.split
      .map { |w| w.match?(/\A\d+\z/) ? (w.sub(/\A0+/, "").presence || "0") : w }
      .select { |w| w.length >= 2 }
      .uniq
  end

  # Two words match fuzzily if one contains the other (for substrings ≥3 chars)
  def fuzzy_match?(word_a, word_b)
    return false if word_a.length < 3 || word_b.length < 3

    word_a.include?(word_b) || word_b.include?(word_a)
  end
end
