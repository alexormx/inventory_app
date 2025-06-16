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

ActiveRecord::Schema[8.0].define(version: 2025_06_16_154008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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

  create_table "cart_items", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_cart_items_on_product_id"
  end

  create_table "inventories", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "purchase_order_id"
    t.string "sale_order_id"
    t.decimal "purchase_cost", precision: 10, scale: 2, null: false
    t.decimal "sold_price", precision: 10, scale: 2
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "status_changed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "purchase_order_item_id"
    t.integer "status", default: 0, null: false
    t.index ["product_id"], name: "index_inventories_on_product_id"
    t.index ["purchase_order_id"], name: "index_inventories_on_purchase_order_id"
    t.index ["sale_order_id"], name: "index_inventories_on_sale_order_id"
  end

  create_table "old_passwords", force: :cascade do |t|
    t.string "encrypted_password", null: false
    t.string "password_archivable_type", null: false
    t.integer "password_archivable_id", null: false
    t.string "password_salt"
    t.datetime "created_at"
    t.index ["password_archivable_type", "password_archivable_id"], name: "index_password_archivable"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "status", default: "Pending", null: false
    t.date "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id", null: false
    t.integer "payment_method"
  end

  create_table "products", force: :cascade do |t|
    t.string "product_sku", null: false
    t.string "barcode"
    t.string "product_name", null: false
    t.string "brand", null: false
    t.string "category", null: false
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
    t.integer "weight_gr", default: 100, null: false
    t.integer "length_cm", default: 16, null: false
    t.integer "width_cm", default: 4, null: false
    t.integer "height_cm", default: 4, null: false
    t.bigint "preferred_supplier_id"
    t.bigint "last_supplier_id"
    t.integer "total_purchase_quantity", default: 0, null: false
    t.decimal "total_purchase_value", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "average_purchase_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "last_purchase_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.date "last_purchase_date"
    t.integer "total_sales_quantity", default: 0, null: false
    t.decimal "average_sales_price", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "last_sales_price", precision: 10, scale: 2, default: "0.0", null: false
    t.date "last_sales_date"
    t.decimal "total_sales_value", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "total_purchase_order", default: 0, null: false
    t.integer "total_sales_order", default: 0, null: false
    t.integer "total_units_sold", default: 0, null: false
    t.decimal "current_profit", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "current_inventory_value", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "projected_sales_value", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "projected_profit", precision: 15, scale: 2, default: "0.0", null: false
    t.string "slug"
    t.index ["last_supplier_id"], name: "index_products_on_last_supplier_id"
    t.index ["preferred_supplier_id"], name: "index_products_on_preferred_supplier_id"
    t.index ["product_sku"], name: "index_products_on_product_sku", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "purchase_order_items", force: :cascade do |t|
    t.string "purchase_order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.decimal "unit_cost", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "unit_additional_cost", precision: 10, scale: 2
    t.decimal "unit_compose_cost", precision: 10, scale: 2
    t.decimal "unit_compose_cost_in_mxn", precision: 10, scale: 2
    t.decimal "total_line_volume", precision: 10, scale: 2
    t.decimal "total_line_weight", precision: 10, scale: 2
    t.decimal "total_line_cost", precision: 10, scale: 2
    t.decimal "total_line_cost_in_mxn", precision: 10, scale: 2
    t.index ["product_id"], name: "index_purchase_order_items_on_product_id"
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
    t.string "currency", default: "MXN", null: false
    t.decimal "exchange_rate", precision: 10, scale: 4, default: "1.0", null: false
    t.decimal "total_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_cost_mxn", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_volume", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_weight", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["user_id"], name: "index_purchase_orders_on_user_id"
  end

  create_table "sale_order_items", force: :cascade do |t|
    t.string "sale_order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.decimal "unit_cost", precision: 10, scale: 2, null: false
    t.decimal "unit_discount", precision: 10, scale: 2, default: "0.0"
    t.decimal "unit_final_price", precision: 10, scale: 2
    t.decimal "total_line_cost", precision: 10, scale: 2
    t.decimal "total_line_volume", precision: 10, scale: 2
    t.decimal "total_line_weight", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_sale_order_items_on_product_id"
  end

  create_table "sale_orders", id: :string, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "order_date", null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.decimal "tax_rate", precision: 5, scale: 2, null: false
    t.decimal "total_tax", precision: 10, scale: 2, null: false
    t.decimal "total_order_value", precision: 10, scale: 2, null: false
    t.decimal "discount", precision: 10, scale: 2
    t.string "status", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sale_orders_on_user_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.string "tracking_number", null: false
    t.string "carrier", null: false
    t.date "estimated_delivery", null: false
    t.date "actual_delivery"
    t.datetime "last_update", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id", null: false
    t.integer "status"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "role", default: "customer", null: false
    t.string "name"
    t.string "phone"
    t.string "address"
    t.string "tax_id"
    t.string "payment_terms"
    t.decimal "discount_rate", precision: 5, scale: 2, default: "0.0"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "timeout_in", default: 21600
    t.datetime "password_changed_at"
    t.datetime "expired_at"
    t.datetime "last_activity_at"
    t.string "unique_session_id"
    t.boolean "created_offline"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["expired_at"], name: "index_users_on_expired_at"
    t.index ["last_activity_at"], name: "index_users_on_last_activity_at"
    t.index ["password_changed_at"], name: "index_users_on_password_changed_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "canceled_order_items", "products"
  add_foreign_key "canceled_order_items", "sale_orders"
  add_foreign_key "cart_items", "products"
  add_foreign_key "inventories", "products"
  add_foreign_key "inventories", "purchase_orders"
  add_foreign_key "inventories", "sale_orders"
  add_foreign_key "old_passwords", "users", column: "password_archivable_id", on_delete: :cascade
  add_foreign_key "payments", "sale_orders"
  add_foreign_key "products", "users", column: "last_supplier_id"
  add_foreign_key "products", "users", column: "preferred_supplier_id"
  add_foreign_key "purchase_order_items", "products"
  add_foreign_key "purchase_order_items", "purchase_orders"
  add_foreign_key "purchase_orders", "users"
  add_foreign_key "sale_order_items", "products"
  add_foreign_key "sale_order_items", "sale_orders"
  add_foreign_key "sale_orders", "users"
  add_foreign_key "shipments", "sale_orders"
end
