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
end
