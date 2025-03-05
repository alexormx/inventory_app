# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_03_05_055515) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "canceled_order_items", force: :cascade do |t|
    t.string "sale_order_id", null: false
    t.bigint "product_id", null: false
    t.integer "canceled_quantity", null: false
    t.decimal "sale_price_at_cancellation", precision: 10, scale: 2, null: false
    t.text "cancellation_reason"
    t.datetime "canceled_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_canceled_order_items_on_product_id"
  end

  create_table "inventories", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "purchase_order_id"
    t.string "sale_order_id"
    t.decimal "purchase_cost", precision: 10, scale: 2, null: false
    t.decimal "sold_price", precision: 10, scale: 2
    t.string "status", default: "Available", null: false
    t.datetime "last_status_change", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_inventories_on_product_id"
    t.index ["purchase_order_id"], name: "index_inventories_on_purchase_order_id"
    t.index ["sale_order_id"], name: "index_inventories_on_sale_order_id"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "payment_method", null: false
    t.string "status", default: "Pending", null: false
    t.date "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id", null: false
  end

  create_table "products", force: :cascade do |t|
    t.string "product_sku", null: false
    t.string "barcode"
    t.string "product_name", null: false
    t.string "brand", null: false
    t.string "category", null: false
    t.bigint "supplier_id", null: false
    t.integer "stock_quantity", default: 0, null: false
    t.integer "reserved_quantity", default: 0, null: false
    t.integer "reorder_point", default: 0, null: false
    t.decimal "selling_price", precision: 10, scale: 2, null: false
    t.decimal "maximum_discount", precision: 10, scale: 2, null: false
    t.integer "discount_limited_stock", default: 0, null: false
    t.decimal "minimum_price", precision: 10, scale: 2, null: false
    t.boolean "backorder_allowed", default: false
    t.boolean "preorder_available", default: false
    t.string "status", default: "Active", null: false
    t.text "product_images"
    t.jsonb "custom_attributes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_sku"], name: "index_products_on_product_sku", unique: true
    t.index ["supplier_id"], name: "index_products_on_supplier_id"
  end

  create_table "purchase_orders", id: :string, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "order_date", null: false
    t.date "expected_delivery_date", null: false
    t.date "actual_delivery_date"
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.decimal "total_order_cost", precision: 10, scale: 2, null: false
    t.string "status", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "shipping_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "tax_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "other_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["user_id"], name: "index_purchase_orders_on_user_id"
  end

  create_table "sale_orders", id: :string, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "order_date", null: false
    t.bigint "payment_id", null: false
    t.bigint "shipment_id", null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.decimal "tax_rate", precision: 5, scale: 2, null: false
    t.decimal "total_tax", precision: 10, scale: 2, null: false
    t.decimal "total_order_value", precision: 10, scale: 2, null: false
    t.decimal "discount", precision: 10, scale: 2
    t.string "status", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id"], name: "index_sale_orders_on_payment_id"
    t.index ["shipment_id"], name: "index_sale_orders_on_shipment_id"
    t.index ["user_id"], name: "index_sale_orders_on_user_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.string "tracking_number", null: false
    t.string "carrier", null: false
    t.string "status", default: "Pending", null: false
    t.date "estimated_delivery", null: false
    t.date "actual_delivery"
    t.datetime "last_update", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "role", default: "customer", null: false
    t.string "name", null: false
    t.string "contact_name", null: false
    t.string "phone", null: false
    t.text "address", null: false
    t.string "tax_id"
    t.string "payment_terms"
    t.decimal "discount_rate", precision: 5, scale: 2
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "canceled_order_items", "products"
  add_foreign_key "canceled_order_items", "sale_orders"
  add_foreign_key "inventories", "products"
  add_foreign_key "inventories", "purchase_orders"
  add_foreign_key "inventories", "sale_orders"
  add_foreign_key "payments", "sale_orders"
  add_foreign_key "products", "users", column: "supplier_id"
  add_foreign_key "purchase_orders", "users"
  add_foreign_key "sale_orders", "payments"
  add_foreign_key "sale_orders", "shipments"
  add_foreign_key "sale_orders", "users"
  add_foreign_key "shipments", "sale_orders"
end
