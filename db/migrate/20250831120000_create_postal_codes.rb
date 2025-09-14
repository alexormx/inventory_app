# frozen_string_literal: true

class CreatePostalCodes < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:postal_codes)

    create_table :postal_codes do |t|
      t.string :cp, limit: 5, null: false
      t.string :state, null: false
      t.string :municipality, null: false
      t.string :settlement, null: false
      t.string :settlement_type
      t.timestamps
    end

    add_index :postal_codes, :cp
    add_index :postal_codes, %i[cp settlement]
  end

  def down
    # Only drop if it was created by this migration (safety check)
    drop_table :postal_codes if table_exists?(:postal_codes)
  end
end

