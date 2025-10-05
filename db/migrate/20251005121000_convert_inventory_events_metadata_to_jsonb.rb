class ConvertInventoryEventsMetadataToJsonb < ActiveRecord::Migration[7.1]
  def up
    return unless postgres?
    # Solo convertir si la columna existe y no es ya jsonb
    col = column_type(:inventory_events, :metadata)
    return if col == :jsonb
    execute <<~SQL
      ALTER TABLE inventory_events
      ALTER COLUMN metadata TYPE jsonb USING metadata::jsonb;
    SQL
    add_index :inventory_events, :metadata, using: :gin
  end

  def down
    return unless postgres?
    # Revertir a json (textual) si fuese necesario
    execute <<~SQL
      ALTER TABLE inventory_events
      ALTER COLUMN metadata TYPE json USING metadata::json;
    SQL
    remove_index :inventory_events, :metadata if index_exists?(:inventory_events, :metadata)
  end

  private
  def postgres?
    ActiveRecord::Base.connection.adapter_name.downcase.include?('postgres')
  end

  def column_type(table, column)
    col = ActiveRecord::Base.connection.columns(table).find { |c| c.name == column.to_s }
    col&.type
  end
end
