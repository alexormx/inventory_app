# frozen_string_literal: true

module VisitorLogsHelper
  # Parsea user-agent y devuelve navegador/dispositivo legible
  def parse_user_agent(user_agent)
    return 'Desconocido' if user_agent.blank?

    browser = detect_browser(user_agent)
    device = detect_device(user_agent)

    "#{browser} / #{device}"
  end

  def detect_browser(ua)
    case ua
    when /Edg/i then 'Edge'
    when /OPR|Opera/i then 'Opera'
    when /Chrome/i then 'Chrome'
    when /Safari/i then 'Safari'
    when /Firefox/i then 'Firefox'
    when /MSIE|Trident/i then 'IE'
    when /bot|crawl|spider/i then 'Bot'
    else 'Otro'
    end
  end

  def detect_device(ua)
    case ua
    when /iPhone/i then 'iPhone'
    when /iPad/i then 'iPad'
    when /Android.*Mobile/i then 'Android'
    when /Android/i then 'Android Tablet'
    when /Windows Phone/i then 'Windows Phone'
    when /Mac OS X/i then 'Mac'
    when /Windows/i then 'Windows'
    when /Linux/i then 'Linux'
    when /bot|crawl|spider/i then 'Bot'
    else 'Otro'
    end
  end

  # Icono según dispositivo
  def device_icon(user_agent)
    return 'fa-robot' if user_agent.to_s =~ /bot|crawl|spider/i

    case user_agent
    when /iPhone|Android.*Mobile|Windows Phone/i then 'fa-mobile-screen'
    when /iPad|Android/i then 'fa-tablet-screen-button'
    else 'fa-desktop'
    end
  end

  # Devuelve código ISO para bandera (2 letras minúsculas)
  def country_flag_code(country_code)
    return nil if country_code.blank?
    return nil unless country_code.to_s.length == 2

    country_code.downcase
  end

  # Bucket a referrer URL into a recognizable traffic source. Returns one
  # of: 'Google', 'Bing', 'Facebook', 'Instagram', 'WhatsApp', 'Twitter/X',
  # 'TikTok', 'YouTube', 'Mercado Libre', 'Directo', or the bare host.
  def referrer_bucket(referrer)
    return 'Directo' if referrer.blank?

    host = URI.parse(referrer).host.to_s.downcase
    return 'Directo' if host.blank?

    case host
    when /\bgoogle\./                       then 'Google'
    when /\bbing\./, /duckduckgo/, /yahoo/  then 'Bing/Otros buscadores'
    when /facebook\.|fb\.me|m\.facebook/    then 'Facebook'
    when /instagram\.|l\.instagram/         then 'Instagram'
    when /whatsapp\.|wa\.me|api\.whatsapp/  then 'WhatsApp'
    when /twitter\.|t\.co|x\.com/           then 'Twitter/X'
    when /tiktok\./                         then 'TikTok'
    when /youtube\.|youtu\.be/              then 'YouTube'
    when /mercadolibre\.|mercadolibre\.com/ then 'Mercado Libre'
    when /pasatiempos\.com\.mx/             then 'Interno'
    else host.sub(/^www\./, '')
    end
  rescue URI::InvalidURIError
    'Directo'
  end

  # Icon for a referrer bucket
  def referrer_icon(bucket)
    case bucket
    when 'Google' then 'fa-brands fa-google'
    when 'Bing/Otros buscadores' then 'fa-solid fa-magnifying-glass'
    when 'Facebook' then 'fa-brands fa-facebook'
    when 'Instagram' then 'fa-brands fa-instagram'
    when 'WhatsApp' then 'fa-brands fa-whatsapp'
    when 'Twitter/X' then 'fa-brands fa-x-twitter'
    when 'TikTok' then 'fa-brands fa-tiktok'
    when 'YouTube' then 'fa-brands fa-youtube'
    when 'Mercado Libre' then 'fa-solid fa-store'
    when 'Directo' then 'fa-solid fa-arrow-right-to-bracket'
    when 'Interno' then 'fa-solid fa-share-nodes'
    else 'fa-solid fa-link'
    end
  end
end
