module ApplicationHelper
  def flash_class(level)
    case level
    when 'notice' then "bg-green-100 text-green-700"
    when 'alert', 'error'
      "bg-red-100 text-red-700"
    else
      "bg-gray-200"
    end
  end
end