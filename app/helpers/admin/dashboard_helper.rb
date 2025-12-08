# frozen_string_literal: true

module Admin
  module DashboardHelper
    include ActionView::Helpers::NumberHelper

    # Devuelve el emoji de bandera dado el nombre de país (en inglés o español común)
    def country_flag_emoji(country_name)
      return '' if country_name.blank?

      iso = country_name_to_iso2(country_name.to_s)
      return '' unless iso && iso.length == 2

      iso = iso.upcase
      base = 0x1F1E6
      a_ord = 'A'.ord
      chars = iso.chars.map { |ch| (base + (ch.ord - a_ord)).chr(Encoding::UTF_8) }
      chars.join
    rescue StandardError
      ''
    end

    # Formateadores compactos y consistentes
    def fmt_currency(value, precision: 2, unit: '$')
      value = begin
        value.to_d
      rescue StandardError
        0.to_d
      end
      "#{unit} #{number_with_precision(value, precision: precision, delimiter: ',')}"
    end

    def fmt_number(value)
      number_with_delimiter(value.to_i)
    end

    def fmt_percentage_ratio(ratio, precision: 1)
      return '—' if ratio.nil?

      number_to_percentage((ratio.to_f * 100.0), precision: precision)
    end

    # Badge para deltas (positivo/negativo)
    def kpi_delta_badge(delta)
      return content_tag(:span, '—', class: 'badge bg-secondary-subtle text-muted') if delta.nil?

      positive = delta.to_f >= 0
      klass = positive ? 'text-success bg-success-subtle' : 'text-danger bg-danger-subtle'
      icon  = positive ? 'fa-arrow-trend-up' : 'fa-arrow-trend-down'
      content_tag(:span, class: "badge #{klass} d-inline-flex align-items-center gap-1") do
        concat(content_tag(:i, '', class: "fa-solid #{icon}"))
        concat(fmt_percentage_ratio(delta))
      end
    end

    # Helper para filas skeleton en tablas (se usa en vistas)
    def table_skeleton_rows(cols:, rows: 3)
      render partial: 'admin/dashboard/table_skeleton', locals: { cols: cols, rows: rows }
    end

    private

    def country_name_to_iso2(name)
      n = I18n.transliterate(name.to_s).downcase.strip
      mapping = {
        'mexico' => 'MX', 'méxico' => 'MX',
        'united states' => 'US', 'usa' => 'US', 'eeuu' => 'US', 'estados unidos' => 'US',
        'canada' => 'CA', 'canadá' => 'CA',
        'guatemala' => 'GT',
        'spain' => 'ES', 'espana' => 'ES', 'españa' => 'ES'
      }
      # match by full token present
      mapping.each do |key, iso|
        return iso if n.include?(key)
      end
      # fallback for exact two-letter ISO already passed
      return name if name.to_s.length == 2

      nil
    end
  end
end

module Admin
  module DashboardHelper
  end
end
