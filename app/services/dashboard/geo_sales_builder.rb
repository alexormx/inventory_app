# frozen_string_literal: true

module Dashboard
  # Builds geographic sales data based on heuristic address parsing.
  # Aggregates by country and Mexican states.
  class GeoSalesBuilder
    attr_reader :now

    def initialize(time_reference: Time.current)
      @now = time_reference
    end

    # Returns geographic sales data for YTD, Last Year, and All Time
    def call
      {
        ytd: geo_for_period(ytd_scope),
        last_year: geo_for_period(last_year_scope),
        all_time: geo_for_period(base_scope)
      }
    end

    # Returns geo data for a single scope (for turbo frame endpoints)
    def geo_for_period(scope)
      country_totals = Hash.new { |h, k| h[k] = { revenue: 0.to_d, orders: 0 } }
      mx_state_totals = Hash.new { |h, k| h[k] = { revenue: 0.to_d, orders: 0 } }

      scope.includes(:user).find_each do |so|
        addr = so.user&.address.to_s
        next if addr.blank?

        norm = normalize_text(addr)
        mx_state = detect_mex_state_in(norm)
        country = detect_country_in(norm)
        country ||= (mx_state ? 'Mexico' : nil)
        country ||= 'Desconocido'

        country_totals[country][:revenue] += so.total_order_value.to_d
        country_totals[country][:orders] += 1

        if country == 'Mexico' && mx_state
          mx_state_totals[mx_state][:revenue] += so.total_order_value.to_d
          mx_state_totals[mx_state][:orders] += 1
        end
      end

      format_results(country_totals, mx_state_totals)
    end

    private

    def format_results(country_totals, mx_state_totals)
      total_rev = country_totals.values.sum { |v| v[:revenue] }

      by_country = country_totals.map do |name, agg|
        share = total_rev.positive? ? (agg[:revenue] / total_rev) : 0.to_d
        {
          name: name,
          orders: agg[:orders],
          revenue: agg[:revenue],
          share: share.round(4)
        }
      end.sort_by { |r| -r[:revenue] }

      by_states = mx_state_totals.map do |state, agg|
        {
          state: state,
          orders: agg[:orders],
          revenue: agg[:revenue]
        }
      end.sort_by { |r| -r[:revenue] }

      { countries: by_country, mexico_states: by_states }
    end

    def ytd_scope
      base_scope.where(order_date: now.beginning_of_year..now.end_of_day)
    end

    def last_year_scope
      ly_start = now.beginning_of_year - 1.year
      base_scope.where(order_date: ly_start..ly_start.end_of_year)
    end

    def base_scope
      SaleOrder.where(status: %w[Confirmed In\ Transit Delivered])
    end

    def normalize_text(text)
      I18n.transliterate(text.to_s).downcase
    end

    def detect_country_in(norm_text)
      return 'Mexico' if norm_text.include?('mexico') || norm_text.include?('méxico')

      if norm_text.include?('estados unidos') || norm_text.include?('eeuu') ||
         norm_text.include?('ee. uu') || norm_text.include?('usa') ||
         norm_text.include?('united states')
        return 'United States'
      end

      return 'Canada' if norm_text.include?('canada')
      return 'Guatemala' if norm_text.include?('guatemala')
      return 'Spain' if norm_text.include?('espana') || norm_text.include?('españa') || norm_text.include?('spain')

      nil
    end

    def detect_mex_state_in(norm_text)
      mexican_states_synonyms.each do |canonical, tokens|
        return canonical if tokens.any? { |tok| norm_text.include?(tok) }
      end
      nil
    end

    def mexican_states_synonyms
      @mexican_states_synonyms ||= {
        'Aguascalientes' => %w[aguascalientes ags],
        'Baja California' => ['baja california', 'bc'],
        'Baja California Sur' => ['baja california sur', 'bcs'],
        'Campeche' => %w[campeche camp],
        'Coahuila' => ['coahuila', 'coah', 'coahuila de zaragoza'],
        'Colima' => ['colima', 'col.'],
        'Chiapas' => %w[chiapas chis],
        'Chihuahua' => %w[chihuahua chih],
        'Ciudad de México' => ['ciudad de mexico', 'cdmx', 'df', 'd.f.', 'mexico city'],
        'Durango' => %w[durango dgo],
        'Guanajuato' => %w[guanajuato gto],
        'Guerrero' => %w[guerrero gro],
        'Hidalgo' => %w[hidalgo hgo],
        'Jalisco' => %w[jalisco jal],
        'Estado de México' => ['estado de mexico', 'edomex', 'mex.', 'mexico state'],
        'Michoacán' => %w[michoacan michoacán mich],
        'Morelos' => %w[morelos mor],
        'Nayarit' => %w[nayarit nay],
        'Nuevo León' => ['nuevo leon', 'nl', 'n.l.'],
        'Oaxaca' => %w[oaxaca oax],
        'Puebla' => %w[puebla pue],
        'Querétaro' => %w[queretaro querétaro qro],
        'Quintana Roo' => ['quintana roo', 'q roo', 'qroo'],
        'San Luis Potosí' => ['san luis potosi', 'slp'],
        'Sinaloa' => %w[sinaloa sin],
        'Sonora' => %w[sonora son],
        'Tabasco' => %w[tabasco tab],
        'Tamaulipas' => %w[tamaulipas tmps tamps],
        'Tlaxcala' => %w[tlaxcala tlax],
        'Veracruz' => ['veracruz', 'ver', 'veracruz de ignacio de la llave'],
        'Yucatán' => %w[yucatan yucatan yuc],
        'Zacatecas' => %w[zacatecas zac]
      }
    end
  end
end
