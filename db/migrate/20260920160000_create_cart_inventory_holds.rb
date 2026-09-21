# frozen_string_literal: true

class CreateCartInventoryHolds < ActiveRecord::Migration[8.0]
  def change
    create_table :cart_inventory_holds do |t|
      t.references :shopping_cart, null: false,
                                   foreign_key: { to_table: :shopping_carts, on_delete: :cascade }
      # One row per physical unit: the unique index is what makes a hold an
      # exclusive claim on an exact Inventory row rather than a quantity.
      t.references :inventory, null: false, index: { unique: true },
                               foreign_key: { to_table: :inventories, on_delete: :cascade }
      # Attribution for per-line release on quantity decrease. Nullify is a
      # defensive backstop only - the normal path releases holds explicitly
      # before the line is deleted.
      t.references :shopping_cart_item, null: true,
                                        foreign_key: { to_table: :shopping_cart_items, on_delete: :nullify }
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :cart_inventory_holds, :expires_at
  end
end
