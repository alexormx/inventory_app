# frozen_string_literal: true

class UpdateLocationTypeIconsToFontAwesome < ActiveRecord::Migration[8.0]
  def up
    # Map Bootstrap Icons to Font Awesome equivalents
    icon_mappings = {
      'bi-building' => 'fas fa-warehouse',
      'bi-grid-3x3-gap' => 'fas fa-th',
      'bi-layout-split' => 'fas fa-columns',
      'bi-arrow-left-right' => 'fas fa-arrows-alt-h',
      'bi-bookshelf' => 'fas fa-box',
      'bi-list-nested' => 'fas fa-layer-group',
      'bi-layers' => 'fas fa-stream',
      'bi-box' => 'fas fa-cube',
      'bi-geo-alt' => 'fas fa-map-marker-alt'
    }

    icon_mappings.each do |old_icon, new_icon|
      execute <<-SQL.squish
        UPDATE location_types SET icon = '#{new_icon}' WHERE icon = '#{old_icon}'
      SQL
    end
  end

  def down
    # Map Font Awesome back to Bootstrap Icons
    icon_mappings = {
      'fas fa-warehouse' => 'bi-building',
      'fas fa-th' => 'bi-grid-3x3-gap',
      'fas fa-columns' => 'bi-layout-split',
      'fas fa-arrows-alt-h' => 'bi-arrow-left-right',
      'fas fa-box' => 'bi-bookshelf',
      'fas fa-layer-group' => 'bi-list-nested',
      'fas fa-stream' => 'bi-layers',
      'fas fa-cube' => 'bi-box',
      'fas fa-map-marker-alt' => 'bi-geo-alt'
    }

    icon_mappings.each do |old_icon, new_icon|
      execute <<-SQL.squish
        UPDATE location_types SET icon = '#{new_icon}' WHERE icon = '#{old_icon}'
      SQL
    end
  end
end
