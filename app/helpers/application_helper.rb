module ApplicationHelper
  def bootstrap_class_for(flash_type)
    case flash_type.to_sym
    when :notice then "alert-success"
    when :alert then "alert-danger"
    when :error then "alert-danger"
    when :warning then "alert-warning"
    else "alert-info"
    end
  end

  def currency_symbol_for(code)
    {
      "MXN" => "$",
      "USD" => "$",
      "EUR" => "€",
      "JPY" => "¥",
      "GBP" => "£",
      "CNY" => "¥",
      "KRW" => "₩"
    }[code] || code
  end

  def language_switcher_enabled?
    SiteSetting.get('language_switcher_enabled', false) && I18n.available_locales.size > 1
  end

  def dark_mode_enabled?
    SiteSetting.get('dark_mode_enabled', false)
  end

  def user_initials(user)
    return "?" unless user&.respond_to?(:name) && user.name.present?
    parts = user.name.split
    (parts.first[0] + (parts.size > 1 ? parts.last[0] : "")).upcase
  end
end
