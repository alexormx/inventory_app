class ChangeStatusToIntegerInInventories < ActiveRecord::Migration[8.0]
  def up
    # Paso 1: Renombra la columna antigua para no perder datos (opcional pero seguro)
    rename_column :inventories, :status, :status_old

    # Paso 2: Agrega la nueva columna enum como integer
    add_column :inventories, :status, :integer, default: 0, null: false

    # Paso 3: Mapear los strings antiguos a sus valores integer
    Inventory.reset_column_information

    Inventory.find_each do |inv|
      inv.update_column(:status, Inventory.statuses[inv.status_old.downcase]) if inv.status_old
    end

    # Paso 4: Eliminar la columna antigua
    remove_column :inventories, :status_old
  end

  def down
    add_column :inventories, :status_old, :string

    Inventory.reset_column_information

    Inventory.find_each do |inv|
      inv.update_column(:status_old, inv.status)
    end

    remove_column :inventories, :status
    rename_column :inventories, :status_old, :status
  end
end
