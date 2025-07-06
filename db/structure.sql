CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "purchase_orders" ("id" varchar NOT NULL PRIMARY KEY, "user_id" integer NOT NULL, "order_date" date NOT NULL, "expected_delivery_date" date NOT NULL, "actual_delivery_date" date, "subtotal" decimal(10,2) NOT NULL, "total_order_cost" decimal(10,2) NOT NULL, "status" varchar NOT NULL, "notes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "shipping_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "tax_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "other_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "currency" varchar DEFAULT 'MXN' NOT NULL, "exchange_rate" decimal(10,4) DEFAULT 1.0 NOT NULL, "total_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "total_cost_mxn" decimal(10,2) DEFAULT 0.0 NOT NULL, "total_volume" decimal(10,2) DEFAULT 0.0 NOT NULL, "total_weight" decimal(10,2) DEFAULT 0.0 NOT NULL, CONSTRAINT "fk_rails_8ffccc9a07"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_purchase_orders_on_user_id" ON "purchase_orders" ("user_id");
CREATE TABLE IF NOT EXISTS "sale_orders" ("id" varchar NOT NULL PRIMARY KEY, "user_id" integer NOT NULL, "order_date" date NOT NULL, "subtotal" decimal(10,2) NOT NULL, "tax_rate" decimal(5,2) NOT NULL, "total_tax" decimal(10,2) NOT NULL, "total_order_value" decimal(10,2) NOT NULL, "discount" decimal(10,2), "status" varchar NOT NULL, "notes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ae66e885f7"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_sale_orders_on_user_id" ON "sale_orders" ("user_id");
CREATE TABLE IF NOT EXISTS "canceled_order_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "sale_order_id" varchar NOT NULL, "product_id" integer NOT NULL, "canceled_quantity" integer NOT NULL, "sale_price_at_cancellation" decimal(10,2) NOT NULL, "cancellation_reason" text, "canceled_at" datetime(6) DEFAULT CURRENT_TIMESTAMP NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8392edddfa"
FOREIGN KEY ("product_id")
  REFERENCES "products" ("id")
, CONSTRAINT "fk_rails_26a03d7591"
FOREIGN KEY ("sale_order_id")
  REFERENCES "sale_orders" ("id")
);
CREATE INDEX "index_canceled_order_items_on_product_id" ON "canceled_order_items" ("product_id");
CREATE TABLE IF NOT EXISTS "users" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email" varchar DEFAULT '' NOT NULL, "encrypted_password" varchar DEFAULT '' NOT NULL, "reset_password_token" varchar, "reset_password_sent_at" datetime(6), "remember_created_at" datetime(6), "role" varchar DEFAULT 'customer' NOT NULL, "name" varchar, "phone" varchar, "address" varchar, "tax_id" varchar, "payment_terms" varchar, "discount_rate" decimal(5,2) DEFAULT 0.0, "notes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "created_offline" boolean, "cookies_accepted" boolean);
CREATE UNIQUE INDEX "index_users_on_email" ON "users" ("email");
CREATE UNIQUE INDEX "index_users_on_reset_password_token" ON "users" ("reset_password_token");
CREATE TABLE IF NOT EXISTS "active_storage_blobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "filename" varchar NOT NULL, "content_type" varchar, "metadata" text, "service_name" varchar NOT NULL, "byte_size" bigint NOT NULL, "checksum" varchar, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_active_storage_blobs_on_key" ON "active_storage_blobs" ("key");
CREATE TABLE IF NOT EXISTS "active_storage_attachments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "record_type" varchar NOT NULL, "record_id" bigint NOT NULL, "blob_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3b3935057"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE INDEX "index_active_storage_attachments_on_blob_id" ON "active_storage_attachments" ("blob_id");
CREATE UNIQUE INDEX "index_active_storage_attachments_uniqueness" ON "active_storage_attachments" ("record_type", "record_id", "name", "blob_id");
CREATE TABLE IF NOT EXISTS "active_storage_variant_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "blob_id" bigint NOT NULL, "variation_digest" varchar NOT NULL, CONSTRAINT "fk_rails_993965df05"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE UNIQUE INDEX "index_active_storage_variant_records_uniqueness" ON "active_storage_variant_records" ("blob_id", "variation_digest");
CREATE TABLE IF NOT EXISTS "purchase_order_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "purchase_order_id" varchar NOT NULL, "product_id" integer NOT NULL, "quantity" integer NOT NULL, "unit_cost" decimal(10,2) NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "unit_additional_cost" decimal(10,2), "unit_compose_cost" decimal(10,2), "unit_compose_cost_in_mxn" decimal(10,2), "total_line_volume" decimal(10,2), "total_line_weight" decimal(10,2), "total_line_cost" decimal(10,2), "total_line_cost_in_mxn" decimal(10,2), CONSTRAINT "fk_rails_d9bc69e4b3"
FOREIGN KEY ("product_id")
  REFERENCES "products" ("id")
, CONSTRAINT "fk_rails_f247068a39"
FOREIGN KEY ("purchase_order_id")
  REFERENCES "purchase_orders" ("id")
);
CREATE INDEX "index_purchase_order_items_on_product_id" ON "purchase_order_items" ("product_id");
CREATE TABLE IF NOT EXISTS "inventories" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "product_id" integer NOT NULL, "purchase_order_id" varchar, "sale_order_id" varchar, "purchase_cost" decimal(10,2) NOT NULL, "sold_price" decimal(10,2), "notes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "status_changed_at" datetime(6) DEFAULT CURRENT_TIMESTAMP NOT NULL, "purchase_order_item_id" integer, "status" integer DEFAULT 0 NOT NULL, CONSTRAINT "fk_rails_427a969329"
FOREIGN KEY ("sale_order_id")
  REFERENCES "sale_orders" ("id")
, CONSTRAINT "fk_rails_fc8a477320"
FOREIGN KEY ("purchase_order_id")
  REFERENCES "purchase_orders" ("id")
, CONSTRAINT "fk_rails_e94eb46135"
FOREIGN KEY ("product_id")
  REFERENCES "products" ("id")
);
CREATE INDEX "index_inventories_on_product_id" ON "inventories" ("product_id");
CREATE INDEX "index_inventories_on_purchase_order_id" ON "inventories" ("purchase_order_id");
CREATE INDEX "index_inventories_on_sale_order_id" ON "inventories" ("sale_order_id");
CREATE TABLE IF NOT EXISTS "products" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "product_sku" varchar NOT NULL, "barcode" varchar, "product_name" varchar NOT NULL, "brand" varchar NOT NULL, "category" varchar NOT NULL, "reorder_point" integer DEFAULT 0 NOT NULL, "selling_price" decimal(10,2) NOT NULL, "maximum_discount" decimal(10,2) NOT NULL, "discount_limited_stock" integer DEFAULT 0 NOT NULL, "minimum_price" decimal(10,2) NOT NULL, "backorder_allowed" boolean DEFAULT 0, "preorder_available" boolean DEFAULT 0, "status" varchar DEFAULT 'Active' NOT NULL, "product_images" text, "custom_attributes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "weight_gr" integer DEFAULT 100 NOT NULL, "length_cm" integer DEFAULT 16 NOT NULL, "width_cm" integer DEFAULT 4 NOT NULL, "height_cm" integer DEFAULT 4 NOT NULL, "preferred_supplier_id" integer, "last_supplier_id" integer, "total_purchase_quantity" integer DEFAULT 0 NOT NULL, "total_purchase_value" decimal(10,2) DEFAULT 0.0 NOT NULL, "average_purchase_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "last_purchase_cost" decimal(10,2) DEFAULT 0.0 NOT NULL, "last_purchase_date" date, "total_sales_quantity" integer DEFAULT 0 NOT NULL, "average_sales_price" decimal(10,2) DEFAULT 0.0 NOT NULL, "last_sales_price" decimal(10,2) DEFAULT 0.0 NOT NULL, "last_sales_date" date, "total_sales_value" decimal(10,2) DEFAULT 0.0 NOT NULL, "total_purchase_order" integer DEFAULT 0 NOT NULL, "total_sales_order" integer DEFAULT 0 NOT NULL, "total_units_sold" integer DEFAULT 0 NOT NULL, "current_profit" decimal(15,2) DEFAULT 0.0 NOT NULL, "current_inventory_value" decimal(15,2) DEFAULT 0.0 NOT NULL, "projected_sales_value" decimal(15,2) DEFAULT 0.0 NOT NULL, "projected_profit" decimal(15,2) DEFAULT 0.0 NOT NULL, "slug" varchar, CONSTRAINT "fk_rails_4a4c6a45b4"
FOREIGN KEY ("preferred_supplier_id")
  REFERENCES "users" ("id")
, CONSTRAINT "fk_rails_9ecc492d8f"
FOREIGN KEY ("last_supplier_id")
  REFERENCES "users" ("id")
);
CREATE UNIQUE INDEX "index_products_on_product_sku" ON "products" ("product_sku");
CREATE INDEX "index_products_on_preferred_supplier_id" ON "products" ("preferred_supplier_id");
CREATE INDEX "index_products_on_last_supplier_id" ON "products" ("last_supplier_id");
CREATE TABLE IF NOT EXISTS "sale_order_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "sale_order_id" varchar NOT NULL, "product_id" integer NOT NULL, "quantity" integer, "unit_cost" decimal(10,2) NOT NULL, "unit_discount" decimal(10,2) DEFAULT 0.0, "unit_final_price" decimal(10,2), "total_line_cost" decimal(10,2), "total_line_volume" decimal(10,2), "total_line_weight" decimal(10,2), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_e973bc2d01"
FOREIGN KEY ("product_id")
  REFERENCES "products" ("id")
, CONSTRAINT "fk_rails_8e8aff3c2f"
FOREIGN KEY ("sale_order_id")
  REFERENCES "sale_orders" ("id")
);
CREATE INDEX "index_sale_order_items_on_product_id" ON "sale_order_items" ("product_id");
CREATE TABLE IF NOT EXISTS "payments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "amount" decimal(10,2) NOT NULL, "status" varchar DEFAULT 'Pending' NOT NULL, "paid_at" date, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "sale_order_id" varchar NOT NULL, "payment_method" integer, CONSTRAINT "fk_rails_03f8d24f3e"
FOREIGN KEY ("sale_order_id")
  REFERENCES "sale_orders" ("id")
);
CREATE TABLE IF NOT EXISTS "shipments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "tracking_number" varchar NOT NULL, "carrier" varchar NOT NULL, "estimated_delivery" date NOT NULL, "actual_delivery" date, "last_update" datetime(6) DEFAULT CURRENT_TIMESTAMP NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "sale_order_id" varchar NOT NULL, "status" integer, CONSTRAINT "fk_rails_a9cffc6597"
FOREIGN KEY ("sale_order_id")
  REFERENCES "sale_orders" ("id")
);
CREATE TABLE IF NOT EXISTS "cart_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "product_id" integer NOT NULL, "quantity" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_681a180e84"
FOREIGN KEY ("product_id")
  REFERENCES "products" ("id")
);
CREATE INDEX "index_cart_items_on_product_id" ON "cart_items" ("product_id");
CREATE UNIQUE INDEX "index_products_on_slug" ON "products" ("slug");
CREATE TABLE IF NOT EXISTS "visitor_logs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "ip_address" varchar, "user_agent" text, "path" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "user_id" integer, "visit_count" integer, "last_visited_at" datetime(6), CONSTRAINT "fk_rails_6017ec9194"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_visitor_logs_on_user_id" ON "visitor_logs" ("user_id");
CREATE UNIQUE INDEX "index_visitor_logs_on_ip_path_user_id" ON "visitor_logs" ("ip_address", "path", "user_id");
INSERT INTO "schema_migrations" (version) VALUES
('20250706143253'),
('20250706031134'),
('20250706021627'),
('20250706015252'),
('20250706014553'),
('20250616154008'),
('20250602000841'),
('20250512040916'),
('20250416050850'),
('20250405145954'),
('20250331053935'),
('20250330165817'),
('20250330160353'),
('20250330044423'),
('20250329201103'),
('20250327045026'),
('20250324043700'),
('20250323214920'),
('20250323083026'),
('20250323081608'),
('20250322185705'),
('20250322041450'),
('20250308030329'),
('20250305055515'),
('20250303054256'),
('20250303050820'),
('20250303050010'),
('20250303044702'),
('20250303044682'),
('20250303044652'),
('20250303044643'),
('20250303044622'),
('20250303044448');

