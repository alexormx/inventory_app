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

ActiveRecord::Schema[8.0].define(version: 2026_02_02_200607) do
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
    t.integer "product_id", null: false
    t.integer "canceled_quantity", null: false
    t.decimal "sale_price_at_cancellation", precision: 10, scale: 2, null: false
    t.text "cancellation_reason"
    t.datetime "canceled_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_canceled_order_items_on_product_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.integer "product_id", null: false
    t.integer "quantity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_cart_items_on_product_id"
  end

  create_table "inventories", force: :cascade do |t|
    t.integer "product_id", null: false
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
    t.integer "sale_order_item_id"
    t.string "source"
    t.string "adjustment_reference"
    t.bigint "inventory_location_id"
    t.integer "item_condition", default: 0, null: false
    t.decimal "selling_price", precision: 10, scale: 2
    t.index ["adjustment_reference"], name: "index_inventories_on_adjustment_reference"
    t.index ["inventory_location_id", "status"], name: "index_inventories_on_inventory_location_id_and_status"
    t.index ["inventory_location_id"], name: "index_inventories_on_inventory_location_id"
    t.index ["item_condition"], name: "index_inventories_on_item_condition"
    t.index ["product_id", "status"], name: "index_inventories_on_product_id_and_status"
    t.index ["product_id"], name: "index_inventories_on_product_id"
    t.index ["purchase_order_id"], name: "index_inventories_on_purchase_order_id"
    t.index ["sale_order_id"], name: "index_inventories_on_sale_order_id"
    t.index ["sale_order_item_id"], name: "index_inventories_on_sale_order_item_id"
    t.index ["source"], name: "index_inventories_on_source"
  end

  create_table "inventory_adjustment_entries", force: :cascade do |t|
    t.integer "inventory_adjustment_line_id", null: false
    t.integer "inventory_id", null: false
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_adjustment_line_id"], name: "idx_adj_entries_line"
    t.index ["inventory_id"], name: "index_inventory_adjustment_entries_on_inventory_id"
  end

  create_table "inventory_adjustment_lines", force: :cascade do |t|
    t.integer "inventory_adjustment_id", null: false
    t.integer "product_id", null: false
    t.integer "quantity", null: false
    t.string "reason"
    t.decimal "unit_cost", precision: 10, scale: 2
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "direction", default: "increase", null: false
    t.index ["direction"], name: "index_inventory_adjustment_lines_on_direction"
    t.index ["inventory_adjustment_id"], name: "index_inventory_adjustment_lines_on_inventory_adjustment_id"
    t.index ["product_id"], name: "index_inventory_adjustment_lines_on_product_id"
  end

  create_table "inventory_adjustments", force: :cascade do |t|
    t.string "code"
    t.string "status", default: "draft", null: false
    t.string "adjustment_type", default: "audit", null: false
    t.datetime "found_at"
    t.string "reference"
    t.text "note"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "applied_at"
    t.integer "applied_by_id"
    t.datetime "reversed_at"
    t.integer "reversed_by_id"
    t.index ["adjustment_type"], name: "index_inventory_adjustments_on_adjustment_type"
    t.index ["applied_at"], name: "index_inventory_adjustments_on_applied_at"
    t.index ["code"], name: "index_inventory_adjustments_on_code", unique: true
    t.index ["found_at"], name: "index_inventory_adjustments_on_found_at"
    t.index ["reversed_at"], name: "index_inventory_adjustments_on_reversed_at"
  end

  create_table "inventory_assignment_logs", force: :cascade do |t|
    t.string "sale_order_id"
    t.bigint "sale_order_item_id"
    t.bigint "product_id"
    t.bigint "inventory_id"
    t.datetime "assigned_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "assignment_type", default: 0, null: false
    t.string "triggered_by", default: "system", null: false
    t.text "notes"
    t.integer "quantity_assigned", default: 1
    t.integer "quantity_pending", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_at"], name: "index_inventory_assignment_logs_on_assigned_at"
    t.index ["assignment_type"], name: "index_inventory_assignment_logs_on_assignment_type"
    t.index ["inventory_id"], name: "index_inventory_assignment_logs_on_inventory_id"
    t.index ["product_id"], name: "index_inventory_assignment_logs_on_product_id"
    t.index ["sale_order_id"], name: "index_inventory_assignment_logs_on_sale_order_id"
    t.index ["sale_order_item_id"], name: "index_inventory_assignment_logs_on_sale_order_item_id"
    t.index ["triggered_by"], name: "index_inventory_assignment_logs_on_triggered_by"
  end

  create_table "inventory_events", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.integer "product_id", null: false
    t.string "event_type", null: false
    t.decimal "previous_purchase_cost", precision: 10, scale: 2
    t.decimal "new_purchase_cost", precision: 10, scale: 2
    t.decimal "previous_sold_price", precision: 10, scale: 2
    t.decimal "new_sold_price", precision: 10, scale: 2
    t.string "previous_sale_order_id"
    t.string "new_sale_order_id"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["created_at"], name: "index_inventory_events_on_created_at"
    t.index ["event_type"], name: "index_inventory_events_on_event_type"
    t.index ["inventory_id"], name: "index_inventory_events_on_inventory_id"
    t.index ["product_id"], name: "index_inventory_events_on_product_id"
  end

  create_table "inventory_locations", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.string "location_type", null: false
    t.text "description"
    t.bigint "parent_id"
    t.integer "position", default: 0
    t.boolean "active", default: true, null: false
    t.integer "depth", default: 0, null: false
    t.string "path_cache"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_inventory_locations_on_active"
    t.index ["code"], name: "index_inventory_locations_on_code", unique: true
    t.index ["location_type"], name: "index_inventory_locations_on_location_type"
    t.index ["parent_id", "position"], name: "index_inventory_locations_on_parent_id_and_position"
    t.index ["parent_id"], name: "index_inventory_locations_on_parent_id"
  end

  create_table "location_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.string "icon", default: "bi-geo-alt"
    t.string "color", default: "secondary"
    t.integer "position", default: 0
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_location_types_on_active"
    t.index ["code"], name: "index_location_types_on_code", unique: true
    t.index ["position"], name: "index_location_types_on_position"
  end

  create_table "maintenance_runs", force: :cascade do |t|
    t.string "job_name", null: false
    t.string "status", default: "queued", null: false
    t.text "stats"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_maintenance_runs_on_created_at"
    t.index ["job_name"], name: "index_maintenance_runs_on_job_name"
    t.index ["status"], name: "index_maintenance_runs_on_status"
  end

  create_table "newsletter_subscribers", force: :cascade do |t|
    t.string "email"
    t.datetime "subscribed_at"
    t.datetime "unsubscribed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_newsletter_subscribers_on_email", unique: true
  end

  create_table "order_shipping_addresses", force: :cascade do |t|
    t.bigint "source_shipping_address_id"
    t.string "full_name", null: false
    t.string "line1", null: false
    t.string "line2"
    t.string "city", null: false
    t.string "state"
    t.string "postal_code", null: false
    t.string "country", null: false
    t.string "shipping_method", null: false
    t.json "raw_address_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id"
    t.index ["sale_order_id"], name: "index_order_shipping_addresses_on_sale_order_id", unique: true
    t.index ["shipping_method"], name: "index_order_shipping_addresses_on_shipping_method"
    t.index ["source_shipping_address_id"], name: "index_order_shipping_addresses_on_source_shipping_address_id"
  end

  create_table "payment_methods", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.text "description"
    t.text "instructions"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_number"
    t.string "account_holder"
    t.string "bank_name"
    t.index ["active"], name: "index_payment_methods_on_active"
    t.index ["code"], name: "index_payment_methods_on_code", unique: true
    t.index ["position"], name: "index_payment_methods_on_position"
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

  create_table "postal_codes", force: :cascade do |t|
    t.string "cp", limit: 5, null: false
    t.string "state", null: false
    t.string "municipality", null: false
    t.string "settlement", null: false
    t.string "settlement_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cp", "settlement"], name: "index_postal_codes_on_cp_and_settlement"
    t.index ["cp"], name: "index_postal_codes_on_cp"
  end

  create_table "preorder_reservations", force: :cascade do |t|
    t.integer "product_id", null: false
    t.integer "user_id", null: false
    t.text "sale_order_id"
    t.integer "quantity", null: false
    t.integer "status", default: 0, null: false
    t.datetime "reserved_at", null: false
    t.datetime "assigned_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "status", "reserved_at"], name: "idx_preorders_fifo"
    t.index ["product_id"], name: "index_preorder_reservations_on_product_id"
    t.index ["sale_order_id"], name: "index_preorder_reservations_on_sale_order_id"
    t.index ["user_id"], name: "index_preorder_reservations_on_user_id"
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
    t.string "status", default: "draft", null: false
    t.text "product_images"
    t.text "custom_attributes", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight_gr", precision: 10, scale: 2, default: "50.0", null: false
    t.decimal "length_cm", precision: 10, scale: 2, default: "8.0", null: false
    t.decimal "width_cm", precision: 10, scale: 2, default: "4.0", null: false
    t.decimal "height_cm", precision: 10, scale: 2, default: "4.0", null: false
    t.integer "preferred_supplier_id"
    t.integer "last_supplier_id"
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
    t.string "whatsapp_code"
    t.text "description"
    t.string "supplier_product_code"
    t.date "launch_date"
    t.boolean "discontinued", default: false, null: false
    t.index "lower((product_name)::text)", name: "index_products_on_lower_product_name"
    t.index ["brand"], name: "index_products_on_brand"
    t.index ["category"], name: "index_products_on_category"
    t.index ["discontinued"], name: "index_products_on_discontinued"
    t.index ["last_supplier_id"], name: "index_products_on_last_supplier_id"
    t.index ["launch_date"], name: "index_products_on_launch_date"
    t.index ["preferred_supplier_id"], name: "index_products_on_preferred_supplier_id"
    t.index ["product_name"], name: "index_products_on_product_name"
    t.index ["product_sku"], name: "index_products_on_product_sku", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "purchase_order_items", force: :cascade do |t|
    t.string "purchase_order_id", null: false
    t.integer "product_id", null: false
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
    t.integer "user_id", null: false
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
    t.string "kind", default: "regular", null: false
    t.datetime "costs_distributed_at"
    t.index ["costs_distributed_at"], name: "index_purchase_orders_on_costs_distributed_at"
    t.index ["kind"], name: "index_purchase_orders_on_kind"
    t.index ["user_id"], name: "index_purchase_orders_on_user_id"
  end

  create_table "sale_order_items", force: :cascade do |t|
    t.string "sale_order_id", null: false
    t.integer "product_id", null: false
    t.integer "quantity"
    t.decimal "unit_cost", precision: 10, scale: 2, null: false
    t.decimal "unit_discount", precision: 10, scale: 2, default: "0.0"
    t.decimal "unit_final_price", precision: 10, scale: 2
    t.decimal "total_line_cost", precision: 10, scale: 2
    t.decimal "total_line_volume", precision: 10, scale: 2
    t.decimal "total_line_weight", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "preorder_quantity", default: 0, null: false
    t.integer "backordered_quantity", default: 0, null: false
    t.integer "item_condition", default: 0, null: false
    t.decimal "unit_selling_price", precision: 10, scale: 2
    t.integer "assigned_quantity", default: 0, null: false
    t.index ["assigned_quantity"], name: "index_sale_order_items_on_assigned_quantity"
    t.index ["backordered_quantity"], name: "index_sale_order_items_on_backordered_quantity"
    t.index ["item_condition"], name: "index_sale_order_items_on_item_condition"
    t.index ["preorder_quantity"], name: "index_sale_order_items_on_preorder_quantity"
    t.index ["product_id"], name: "index_sale_order_items_on_product_id"
  end

  create_table "sale_orders", id: :string, force: :cascade do |t|
    t.integer "user_id", null: false
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
    t.decimal "shipping_cost", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "credit_override", default: false, null: false
    t.string "credit_terms"
    t.date "due_date"
    t.string "idempotency_key"
    t.index ["credit_override"], name: "index_sale_orders_on_credit_override"
    t.index ["due_date"], name: "index_sale_orders_on_due_date"
    t.index ["user_id", "idempotency_key"], name: "index_sale_orders_on_user_and_idempotency", unique: true
    t.index ["user_id"], name: "index_sale_orders_on_user_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.string "tracking_number", null: false
    t.string "carrier", null: false
    t.date "estimated_delivery", null: false
    t.date "actual_delivery"
    t.datetime "last_update", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sale_order_id", null: false
    t.integer "status"
    t.decimal "shipping_cost", precision: 10, scale: 2, default: "0.0", null: false
  end

  create_table "shipping_addresses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "label", default: "Principal", null: false
    t.string "full_name", null: false
    t.string "line1", null: false
    t.string "line2"
    t.string "city", null: false
    t.string "state"
    t.string "postal_code", null: false
    t.string "country", default: "MX", null: false
    t.boolean "default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "settlement"
    t.string "municipality"
    t.index ["postal_code"], name: "index_shipping_addresses_on_postal_code"
    t.index ["user_id", "default"], name: "index_shipping_addresses_on_user_id_and_default"
    t.index ["user_id"], name: "index_shipping_addresses_on_user_id"
  end

  create_table "shipping_methods", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.text "description"
    t.decimal "base_cost", precision: 10, scale: 2, default: "0.0"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_shipping_methods_on_active"
    t.index ["code"], name: "index_shipping_methods_on_code", unique: true
    t.index ["position"], name: "index_shipping_methods_on_position"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.string "value_type", default: "string", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_site_settings_on_key", unique: true
  end

  create_table "system_variables", force: :cascade do |t|
    t.string "name", null: false
    t.string "value"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_system_variables_on_name", unique: true
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
    t.boolean "created_offline"
    t.boolean "cookies_accepted"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "api_token"
    t.boolean "credit_enabled", default: false, null: false
    t.string "default_credit_terms", default: "none", null: false
    t.decimal "credit_limit", precision: 12, scale: 2
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["credit_enabled"], name: "index_users_on_credit_enabled"
    t.index ["default_credit_terms"], name: "index_users_on_default_credit_terms"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "visitor_logs", force: :cascade do |t|
    t.string "ip_address"
    t.text "user_agent"
    t.string "path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "visit_count"
    t.datetime "last_visited_at"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.index ["ip_address", "path", "user_id"], name: "index_visitor_logs_on_ip_path_user_id", unique: true
    t.index ["user_id"], name: "index_visitor_logs_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "canceled_order_items", "products"
  add_foreign_key "canceled_order_items", "sale_orders"
  add_foreign_key "cart_items", "products"
  add_foreign_key "inventories", "inventory_locations"
  add_foreign_key "inventories", "products"
  add_foreign_key "inventories", "purchase_orders"
  add_foreign_key "inventories", "sale_orders"
  add_foreign_key "inventory_assignment_logs", "inventories"
  add_foreign_key "inventory_assignment_logs", "products"
  add_foreign_key "inventory_assignment_logs", "sale_order_items"
  add_foreign_key "inventory_assignment_logs", "sale_orders"
  add_foreign_key "inventory_events", "inventories"
  add_foreign_key "inventory_events", "products"
  add_foreign_key "inventory_locations", "inventory_locations", column: "parent_id"
  add_foreign_key "order_shipping_addresses", "sale_orders"
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
  add_foreign_key "shipping_addresses", "users"
  add_foreign_key "visitor_logs", "users"
end
