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

  def inventory_status_label(status)
    case status.to_s
    when "available"  then "Disponible"
    when "reserved"   then "Apartado"
    when "in_transit" then "En tránsito"
    when "sold"       then "Vendido"
    when "damaged"    then "Dañado"
    when "lost"       then "Perdido"
    when "scrap"      then "Scrap"
    when "returned"   then "Devuelto"
    else status.to_s.humanize
    end
  end
end