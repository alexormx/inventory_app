# frozen_string_literal: true

# Claves de API para integraciones (KataFrame). Solo se guarda el digest
# SHA-256 del token; el token en claro se muestra una sola vez al crearla.
class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :scopes, array: true, default: [], null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true
  end
end
