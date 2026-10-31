# frozen_string_literal: true

# Distingue las cuentas que el cliente creó en el registro público de las que
# crea el admin o la API (esas se confirman al crearse con skip_confirmation!).
class AddSelfRegisteredToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :self_registered, :boolean, default: false, null: false

    # Solo el registro público envía el correo de confirmación al crear la
    # cuenta; admin y API lo omiten, así que confirmation_sent_at los separa.
    execute <<~SQL.squish
      UPDATE users SET self_registered = TRUE
      WHERE role = 'customer' AND confirmation_sent_at IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :self_registered
  end
end
