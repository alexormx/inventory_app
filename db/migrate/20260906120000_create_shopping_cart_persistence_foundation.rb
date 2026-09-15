# frozen_string_literal: true

# Persistence foundation for the future shopping cart (PR A of the approved
# architecture). Purely additive: the storefront still reads/writes
# session[:cart] via the existing Cart PORO. No storefront code is wired to
# these tables yet - that happens in a later PR once import/reconciliation
# exists.
class CreateShoppingCartPersistenceFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :shopping_carts do |t|
      # Nullable: an anonymous cart has no user until claimed at login.
      t.references :user, null: true, foreign_key: true
      # String, not an integer enum: mirrors SaleOrder/Payment's lifecycle
      # status columns (business-meaningful, human-readable in raw SQL and in
      # the partial-index predicates below) rather than Inventory/Shipment's
      # technical integer enums.
      t.string :status, null: false, default: 'active'
      t.string :anonymous_token_digest
      # Named lock_version so ActiveRecord's built-in optimistic locking
      # (Locking::Optimistic) picks it up with zero extra configuration.
      t.integer :lock_version, null: false, default: 0
      t.datetime :last_activity_at, null: false
      t.datetime :converted_at
      t.datetime :closed_at
      # SaleOrder's primary key is a string (e.g. "SO-202609-001"), so this
      # must match exactly - a plain t.references would default to bigint.
      t.references :sale_order, type: :string, null: true, foreign_key: true, index: { unique: true }
      t.references :merged_into_cart, null: true, foreign_key: { to_table: :shopping_carts }

      t.timestamps
    end

    # At most one ACTIVE cart per authenticated user. Terminal carts
    # (converted/merged/cleared) are historical and may accumulate freely.
    add_index :shopping_carts, :user_id, unique: true,
                                          where: "status = 'active' AND user_id IS NOT NULL",
                                          name: 'index_shopping_carts_on_user_id_when_active'
    # Postgres unique indexes already treat NULL as distinct from other NULLs,
    # so a plain unique index is sufficient for "unique when present".
    add_index :shopping_carts, :anonymous_token_digest, unique: true,
                                                          where: 'anonymous_token_digest IS NOT NULL',
                                                          name: 'index_shopping_carts_on_anon_token_digest'
    add_index :shopping_carts, %i[user_id created_at], name: 'index_shopping_carts_on_user_id_and_created_at'
    # Supports a future "carts idle longer than N" scan without touching
    # historical (non-active) rows.
    add_index :shopping_carts, :last_activity_at, where: "status = 'active'",
                                                   name: 'index_shopping_carts_on_last_activity_when_active'

    # Full lifecycle matrix enforced at the DB level (not just in the model),
    # since concurrent writers must not be able to race past a Rails
    # validation into an inconsistent terminal state.
    add_check_constraint :shopping_carts, <<~SQL.squish, name: 'shopping_carts_lifecycle_invariants'
      (status = 'active' AND sale_order_id IS NULL AND converted_at IS NULL AND closed_at IS NULL AND merged_into_cart_id IS NULL)
      OR (status = 'converted' AND sale_order_id IS NOT NULL AND converted_at IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL)
      OR (status = 'merged' AND merged_into_cart_id IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL)
      OR (status = 'cleared' AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL)
    SQL
    add_check_constraint :shopping_carts, 'merged_into_cart_id IS NULL OR merged_into_cart_id != id',
                          name: 'shopping_carts_no_self_merge'

    create_table :shopping_cart_items do |t|
      t.references :shopping_cart, null: false, foreign_key: true
      # Nullable + ON DELETE SET NULL: a deleted product must not destroy the
      # historical cart line. product_reference (below) is what survives.
      t.references :product, null: true, foreign_key: { on_delete: :nullify }
      # The canonical Product identifier (Product#id), copied at add-time so
      # it survives product deletion. Deliberately NOT a foreign key.
      t.bigint :product_reference, null: false
      t.integer :condition, null: false, default: 0
      t.integer :quantity, null: false
      t.string :product_name_snapshot

      t.timestamps
    end

    add_index :shopping_cart_items, %i[shopping_cart_id product_reference condition], unique: true,
              name: 'index_cart_items_on_cart_product_ref_and_condition'
    add_check_constraint :shopping_cart_items, 'quantity > 0', name: 'shopping_cart_items_quantity_positive'
    # Technical safety net only (protects against malformed/overflow input) -
    # not a business cap. The 1-piece/3-piece collectible limits stay
    # application-level so a future login merge can surface a conflicting
    # quantity above the mutation cap instead of silently clamping it.
    add_check_constraint :shopping_cart_items, 'quantity <= 100000', name: 'shopping_cart_items_quantity_bounded'

    create_table :cart_session_imports do |t|
      t.references :shopping_cart, null: false, foreign_key: { on_delete: :restrict }
      t.string :import_key_digest, null: false
      t.string :source_payload_digest, null: false
      # session[:cart] is bounded by this app's 4KB cookie session store (see
      # 20260821111131_create_location_assignment_drafts.rb), so its shape -
      # a small nested hash of product_id => condition => quantity - is
      # inherently small. jsonb is appropriate; the check constraint below is
      # a defensive margin in case that upstream assumption ever changes.
      t.jsonb :source_payload, null: false, default: {}

      t.timestamps
    end

    add_index :cart_session_imports, :import_key_digest, unique: true,
                                                          name: 'index_cart_session_imports_on_import_key_digest'
    add_check_constraint :cart_session_imports, 'octet_length(source_payload::text) <= 8192',
                          name: 'cart_session_imports_payload_bounded'
  end
end
