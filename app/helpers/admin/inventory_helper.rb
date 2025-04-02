module Admin::InventoryHelper
  def inventory_status_color(status)
    case status.to_s
    when "available"  then "success"
    when "reserved"   then "info"
    when "in_transit" then "primary"
    when "sold"       then "secondary"
    when "damaged"    then "warning"
    when "lost"       then "dark"
    when "scrap"      then "danger"
    when "returned"   then "light"
    else "secondary"
    end
  end
end