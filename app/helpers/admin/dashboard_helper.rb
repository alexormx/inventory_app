module Admin
  module DashboardHelper
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
    rescue
      ''
    end

    private
    def country_name_to_iso2(name)
      n = I18n.transliterate(name.to_s).downcase.strip
      mapping = {
        'mexico' => 'MX', 'méxico' => 'MX',
        'united states' => 'US', 'usa' => 'US', 'eeuu' => 'US', 'estados unidos' => 'US',
        'canada' => 'CA', 'canadá' => 'CA',
        'guatemala' => 'GT',
        'spain' => 'ES', 'espana' => 'ES', 'españa' => 'ES',
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
module Admin::DashboardHelper
end
