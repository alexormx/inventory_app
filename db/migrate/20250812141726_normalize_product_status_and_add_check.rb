# frozen_string_literal: true

class NormalizeProductStatusAndAddCheck < ActiveRecord::Migration[8.0]
  def up
    # 1) Normalize current values ('Active' -> 'active', nil/unknown -> 'inactive')
    execute <<~SQL.squish
      UPDATE products
         SET status = LOWER(COALESCE(status, 'inactive'));
      UPDATE products
         SET status = 'inactive'
       WHERE status NOT IN ('draft','active','inactive');
    SQL

    # 2) DB default → 'draft' (safer for imports; nothing goes public by accident)
    change_column_default :products, :status, from: 'Active', to: 'draft'

    # 3) Optional but recommended on Postgres: prevent invalid statuses at DB level
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?('postgres')

    execute <<~SQL.squish
      ALTER TABLE products
      DROP CONSTRAINT IF EXISTS products_status_check;
      ALTER TABLE products
      ADD CONSTRAINT products_status_check
      CHECK (status IN ('draft','active','inactive'));
    SQL
  end

  def down
    change_column_default :products, :status, from: 'draft', to: 'Active'
    return unless ActiveRecord::Base.connection.adapter_name.downcase.include?('postgres')

    execute 'ALTER TABLE products DROP CONSTRAINT IF EXISTS products_status_check;'

  end
end
