# frozen_string_literal: true

module InventoryLocationsHelper
  # Returns a Bootstrap color class based on location type
  def location_type_color(location_type)
    colors = {
      'warehouse' => 'primary',
      'zone' => 'info',
      'section' => 'success',
      'aisle' => 'warning',
      'rack' => 'danger',
      'shelf' => 'secondary',
      'level' => 'dark',
      'bin' => 'primary',
      'position' => 'info'
    }
    colors[location_type] || 'secondary'
  end

  # Returns an icon class based on location type
  def location_type_icon(location_type)
    icons = {
      'warehouse' => 'bi-building',
      'zone' => 'bi-grid-3x3-gap',
      'section' => 'bi-layout-split',
      'aisle' => 'bi-arrow-left-right',
      'rack' => 'bi-bookshelf',
      'shelf' => 'bi-list-nested',
      'level' => 'bi-layers',
      'bin' => 'bi-box',
      'position' => 'bi-geo-alt'
    }
    icons[location_type] || 'bi-geo'
  end
end
