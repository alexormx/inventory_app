class ChangePreorderReservationsSaleOrderIdToString < ActiveRecord::Migration[8.0]
  def up
    if sqlite?
      # Detectar tipo actual
      col = execute("PRAGMA table_info(preorder_reservations)").to_a.find { |r| r[1] == "sale_order_id" }
      current_type = col && col[2]
      return if current_type && current_type.downcase == 'text'

      # Recrear la tabla para cambiar tipo en SQLite
      execute <<~SQL
        PRAGMA foreign_keys=OFF;
        BEGIN TRANSACTION;
        CREATE TABLE preorder_reservations_new (
          id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          product_id integer NOT NULL,
          user_id integer NOT NULL,
          sale_order_id text,
          quantity integer NOT NULL,
          status integer DEFAULT 0 NOT NULL,
          reserved_at datetime(6) NOT NULL,
          assigned_at datetime(6),
          completed_at datetime(6),
          cancelled_at datetime(6),
          notes text,
          created_at datetime(6) NOT NULL,
          updated_at datetime(6) NOT NULL
        );
        INSERT INTO preorder_reservations_new (
          id, product_id, user_id, sale_order_id, quantity, status, reserved_at, assigned_at, completed_at, cancelled_at, notes, created_at, updated_at
        )
        SELECT id, product_id, user_id, CAST(sale_order_id AS TEXT), quantity, status, reserved_at, assigned_at, completed_at, cancelled_at, notes, created_at, updated_at
        FROM preorder_reservations;
        DROP TABLE preorder_reservations;
        ALTER TABLE preorder_reservations_new RENAME TO preorder_reservations;
        CREATE INDEX index_preorder_reservations_on_product_id ON preorder_reservations(product_id);
        CREATE INDEX index_preorder_reservations_on_user_id ON preorder_reservations(user_id);
        CREATE INDEX index_preorder_reservations_on_sale_order_id ON preorder_reservations(sale_order_id);
        CREATE INDEX idx_preorders_fifo ON preorder_reservations(product_id, status, reserved_at);
        COMMIT;
        PRAGMA foreign_keys=ON;
      SQL

      # Re-crear FKs (SQLite ignora FKs en ALTER; se definen al crear tabla). Si hay validación, no hace falta aquí.
    else
      # Postgres / otros
      remove_foreign_key :preorder_reservations, :sale_orders if foreign_key_exists?(:preorder_reservations, :sale_orders)
      change_column :preorder_reservations, :sale_order_id, :string
      add_foreign_key :preorder_reservations, :sale_orders
    end
  end

  def down
    if sqlite?
      # Volver a integer solo si actualmente es text
      col = execute("PRAGMA table_info(preorder_reservations)").to_a.find { |r| r[1] == "sale_order_id" }
      current_type = col && col[2]
      return if current_type && current_type.downcase == 'integer'

      execute <<~SQL
        PRAGMA foreign_keys=OFF;
        BEGIN TRANSACTION;
        CREATE TABLE preorder_reservations_new (
          id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          product_id integer NOT NULL,
          user_id integer NOT NULL,
          sale_order_id integer,
          quantity integer NOT NULL,
          status integer DEFAULT 0 NOT NULL,
          reserved_at datetime(6) NOT NULL,
          assigned_at datetime(6),
          completed_at datetime(6),
          cancelled_at datetime(6),
          notes text,
          created_at datetime(6) NOT NULL,
          updated_at datetime(6) NOT NULL
        );
        INSERT INTO preorder_reservations_new (
          id, product_id, user_id, sale_order_id, quantity, status, reserved_at, assigned_at, completed_at, cancelled_at, notes, created_at, updated_at
        )
        SELECT id, product_id, user_id, CAST(sale_order_id AS INTEGER), quantity, status, reserved_at, assigned_at, completed_at, cancelled_at, notes, created_at, updated_at
        FROM preorder_reservations;
        DROP TABLE preorder_reservations;
        ALTER TABLE preorder_reservations_new RENAME TO preorder_reservations;
        CREATE INDEX index_preorder_reservations_on_product_id ON preorder_reservations(product_id);
        CREATE INDEX index_preorder_reservations_on_user_id ON preorder_reservations(user_id);
        CREATE INDEX index_preorder_reservations_on_sale_order_id ON preorder_reservations(sale_order_id);
        CREATE INDEX idx_preorders_fifo ON preorder_reservations(product_id, status, reserved_at);
        COMMIT;
        PRAGMA foreign_keys=ON;
      SQL
    else
      remove_foreign_key :preorder_reservations, :sale_orders if foreign_key_exists?(:preorder_reservations, :sale_orders)
      change_column :preorder_reservations, :sale_order_id, :integer
      add_foreign_key :preorder_reservations, :sale_orders
    end
  end

  private
  def sqlite?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
  end
end
