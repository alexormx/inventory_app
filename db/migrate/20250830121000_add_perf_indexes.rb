class AddPerfIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :inventories, [:product_id, :status]
    add_index :products, :product_name unless index_exists?(:products, :product_name)
    add_index :products, :brand unless index_exists?(:products, :brand)
    add_index :products, :category unless index_exists?(:products, :category)
    # Functional index para búsquedas case-insensitive (PostgreSQL). Ignorado en SQLite.
    reversible do |dir|
      dir.up do
        execute <<~SQL rescue nil
          CREATE INDEX index_products_on_lower_product_name ON products (lower(product_name));
        SQL
      end
      dir.down do
        execute <<~SQL rescue nil
          DROP INDEX index_products_on_lower_product_name;
        SQL
      end
    end
  end
end