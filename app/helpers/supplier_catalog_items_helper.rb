module SupplierCatalogItemsHelper
  def name_similarity_score(a, b)
    words_a = a.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split.select { |w| w.length >= 2 }.to_set
    words_b = b.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split.select { |w| w.length >= 2 }.to_set
    return 0.0 if words_a.empty? || words_b.empty?

    intersection = (words_a & words_b).size.to_f
    intersection / [words_a.size, words_b.size].max
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
end
