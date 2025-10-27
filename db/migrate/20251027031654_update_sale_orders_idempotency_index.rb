class UpdateSaleOrdersIdempotencyIndex < ActiveRecord::Migration[8.0]
  def up
    remove_index :sale_orders, column: :idempotency_key if index_exists?(:sale_orders, :idempotency_key)

    add_index :sale_orders, [:user_id, :idempotency_key],
              unique: true,
              name: "index_sale_orders_on_user_and_idempotency" unless index_exists?(
                :sale_orders,
                [:user_id, :idempotency_key],
                unique: true,
                name: "index_sale_orders_on_user_and_idempotency"
              )
  end

  def down
    remove_index :sale_orders,
                 name: "index_sale_orders_on_user_and_idempotency" if index_exists?(
                   :sale_orders,
                   [:user_id, :idempotency_key],
                   unique: true,
                   name: "index_sale_orders_on_user_and_idempotency"
                 )

    add_index :sale_orders, :idempotency_key unless index_exists?(:sale_orders, :idempotency_key)
  end
end
