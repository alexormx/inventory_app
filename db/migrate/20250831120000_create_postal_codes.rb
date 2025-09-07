class CreatePostalCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :postal_codes do |t|
      t.string :cp, null: false, limit: 5
      t.string :state, null: false
      t.string :municipality, null: false
      t.string :settlement, null: false
      t.string :settlement_type
      t.timestamps
    end
    add_index :postal_codes, :cp
    add_index :postal_codes, [:cp, :settlement]
  end
end
