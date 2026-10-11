# frozen_string_literal: true

# Carritos que vencen tras 4 h sin cambios (estado terminal `expired`) y notas
# de checkout guardadas en el carrito en vez de la cookie de sesión.
class AddExpiredStatusAndNotesToShoppingCarts < ActiveRecord::Migration[8.0]
  OLD = <<~SQL.squish
    status::text = 'active'::text AND sale_order_id IS NULL AND converted_at IS NULL AND closed_at IS NULL AND merged_into_cart_id IS NULL
    OR status::text = 'converted'::text AND sale_order_id IS NOT NULL AND converted_at IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
    OR status::text = 'merged'::text AND merged_into_cart_id IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
    OR status::text = 'cleared'::text AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
  SQL
  NEW = "#{OLD} OR status::text = 'expired'::text AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL".freeze

  def up
    add_column :shopping_carts, :checkout_notes, :text
    remove_check_constraint :shopping_carts, name: 'shopping_carts_lifecycle_invariants'
    add_check_constraint :shopping_carts, NEW, name: 'shopping_carts_lifecycle_invariants'
  end

  def down
    execute "UPDATE shopping_carts SET status = 'cleared' WHERE status = 'expired'"
    remove_check_constraint :shopping_carts, name: 'shopping_carts_lifecycle_invariants'
    add_check_constraint :shopping_carts, OLD, name: 'shopping_carts_lifecycle_invariants'
    remove_column :shopping_carts, :checkout_notes
  end
end
