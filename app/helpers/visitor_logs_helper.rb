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

    country_code.downcase
  end
end
