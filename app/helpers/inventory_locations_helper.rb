# frozen_string_literal: true

module InventoryLocationsHelper
  # Returns a Bootstrap color class based on location type (from LocationType model)
  def location_type_color(location_type)
    LocationType.color_for(location_type)
  end

  # Returns an icon class based on location type (from LocationType model)
  def location_type_icon(location_type)
    LocationType.icon_for(location_type)
  end
end
