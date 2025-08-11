class AddCustomAttributesGuards < ActiveRecord::Migration[8.0]
  def up
    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    if adapter.start_with?('sqlite')
      # SQLite path (column is TEXT in your CreateProducts)
      # 1) Ensure default "{}" at DB level (as a string literal)
      change_column_default :products, :custom_attributes, from: nil, to: "{}"

      # 2) Backfill NULLs to "{}"
      execute <<~SQL
        UPDATE products
        SET custom_attributes = '{}'
        WHERE custom_attributes IS NULL;
      SQL

      # 3) Skip CHECK constraint and GIN index (not supported on SQLite)
    else
      # Postgres path (column is jsonb in your CreateProducts)
      # 1) Ensure default {} at DB level
      change_column_default :products, :custom_attributes, from: nil, to: {}

      # 2) Backfill NULLs to {}
      execute <<~SQL
        UPDATE products
        SET custom_attributes = '{}'::jsonb
        WHERE custom_attributes IS NULL;
      SQL

      # 3) Enforce object shape
      add_check_constraint :products,
        "jsonb_typeof(custom_attributes) = 'object'",
        name: "custom_attributes_is_object"

      # 4) JSON performance index
      add_index :products, :custom_attributes,
                using: :gin,
                name: "index_products_on_custom_attributes_gin"
    end
  end

  def down
    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    if adapter.start_with?('sqlite')
      change_column_default :products, :custom_attributes, from: "{}", to: nil
      # nothing to remove for constraints/index (we didn’t add them)
    else
      remove_index :products, name: "index_products_on_custom_attributes_gin"
      remove_check_constraint :products, name: "custom_attributes_is_object"
      change_column_default :products, :custom_attributes, from: {}, to: nil
    end
  end
end
