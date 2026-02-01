class SeedDefaultLocationTypes < ActiveRecord::Migration[8.0]
  def up
    # Seed default location types
    defaults = [
      { code: 'warehouse', name: 'Bodega', icon: 'bi-building', color: 'primary', position: 0 },
      { code: 'zone', name: 'Zona', icon: 'bi-grid-3x3-gap', color: 'info', position: 1 },
      { code: 'section', name: 'Sección', icon: 'bi-layout-split', color: 'success', position: 2 },
      { code: 'aisle', name: 'Pasillo', icon: 'bi-arrow-left-right', color: 'warning', position: 3 },
      { code: 'rack', name: 'Estante', icon: 'bi-bookshelf', color: 'danger', position: 4 },
      { code: 'shelf', name: 'Anaquel', icon: 'bi-list-nested', color: 'secondary', position: 5 },
      { code: 'level', name: 'Nivel', icon: 'bi-layers', color: 'dark', position: 6 },
      { code: 'bin', name: 'Contenedor', icon: 'bi-box', color: 'primary', position: 7 },
      { code: 'position', name: 'Posición', icon: 'bi-geo-alt', color: 'info', position: 8 }
    ]

    defaults.each do |attrs|
      execute <<-SQL
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
