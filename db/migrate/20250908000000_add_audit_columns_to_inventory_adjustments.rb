# frozen_string_literal: true

class AddAuditColumnsToInventoryAdjustments < ActiveRecord::Migration[8.0]
  # Migración convertida en no-op porque las columnas base ya existen en la creación inicial
  # Se deja estructura por historial; no realiza cambios para evitar errores en entornos donde ya se aplicó.
  def up
    # NOP
  end

  def down
    # NOP
  end
end
