class ChangeDimensionsToDecimalOnProducts < ActiveRecord::Migration[8.0]
  def change
    # Cambiar columnas: usar change_column si DB soporta conversión implícita
    change_column :products, :weight_gr, :decimal, precision: 10, scale: 2, default: 50.0, null: false
    change_column :products, :length_cm, :decimal, precision: 10, scale: 2, default: 8.0, null: false
    change_column :products, :width_cm,  :decimal, precision: 10, scale: 2, default: 4.0, null: false
    change_column :products, :height_cm, :decimal, precision: 10, scale: 2, default: 4.0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE products
          SET weight_gr = 50.0,
              length_cm = 8.0,
              width_cm  = 4.0,
              height_cm = 4.0
          WHERE weight_gr IS NULL OR weight_gr = 0
             OR length_cm IS NULL OR length_cm = 0
             OR width_cm  IS NULL OR width_cm = 0
             OR height_cm IS NULL OR height_cm = 0;
        SQL
      end
    end
  end
end
