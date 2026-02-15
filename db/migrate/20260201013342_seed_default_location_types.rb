# frozen_string_literal: true

class SeedDefaultLocationTypes < ActiveRecord::Migration[8.0]
  def up
    # Seed default location types (using Font Awesome icons)
    defaults = [
      { code: 'warehouse', name: 'Bodega', icon: 'fas fa-warehouse', color: 'primary', position: 0 },
      { code: 'zone', name: 'Zona', icon: 'fas fa-th', color: 'info', position: 1 },
      { code: 'section', name: 'Sección', icon: 'fas fa-columns', color: 'success', position: 2 },
      { code: 'aisle', name: 'Pasillo', icon: 'fas fa-arrows-alt-h', color: 'warning', position: 3 },
      { code: 'rack', name: 'Estante', icon: 'fas fa-box', color: 'danger', position: 4 },
      { code: 'shelf', name: 'Anaquel', icon: 'fas fa-layer-group', color: 'secondary', position: 5 },
      { code: 'level', name: 'Nivel', icon: 'fas fa-stream', color: 'dark', position: 6 },
      { code: 'bin', name: 'Contenedor', icon: 'fas fa-cube', color: 'primary', position: 7 },
      { code: 'position', name: 'Posición', icon: 'fas fa-map-marker-alt', color: 'info', position: 8 }
    ]

    defaults.each do |attrs|
      execute <<-SQL.squish
        INSERT INTO location_types (code, name, icon, color, position, active, created_at, updated_at)
        VALUES ('#{attrs[:code]}', '#{attrs[:name]}', '#{attrs[:icon]}', '#{attrs[:color]}', #{attrs[:position]}, true, NOW(), NOW())
        ON CONFLICT (code) DO NOTHING
      SQL
    end
  end

  def down
    # Don't remove data on rollback
  end
end
