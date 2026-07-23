# frozen_string_literal: true

class AddCatalogEventTimestampsToProducts < ActiveRecord::Migration[8.0]
  def up
    add_column :products, :first_published_at, :datetime
    add_column :products, :republished_at, :datetime
    add_column :products, :first_stocked_at, :datetime
    add_column :products, :restocked_at, :datetime

    add_index :products, :first_published_at
    add_index :products, :republished_at
    add_index :products, :restocked_at

    # Backfill so existing catalog never spuriously badges and future restocks
    # are correctly distinguished from the initial inventory load.
    say_with_time 'Backfilling first_published_at for active products' do
      execute <<~SQL.squish
        UPDATE products
        SET first_published_at = created_at
        WHERE status = 'active' AND first_published_at IS NULL
      SQL
    end

    say_with_time 'Backfilling first_stocked_at for products with available stock' do
      execute <<~SQL.squish
        UPDATE products
        SET first_stocked_at = created_at
        WHERE first_stocked_at IS NULL
          AND id IN (SELECT DISTINCT product_id FROM inventories WHERE status = 0)
      SQL
    end
  end

  def down
    remove_column :products, :first_published_at
    remove_column :products, :republished_at
    remove_column :products, :first_stocked_at
    remove_column :products, :restocked_at
  end
end
