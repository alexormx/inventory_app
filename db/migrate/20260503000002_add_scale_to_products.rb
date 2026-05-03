# frozen_string_literal: true

# Promueve `escala` a una columna de primer nivel en products. Antes vivía como
# clave dentro de `custom_attributes` (JSON). Esta migración:
#   1. Agrega las columnas scale y show_scale_publicly.
#   2. Copia los valores existentes de custom_attributes['escala'] a la nueva
#      columna scale.
#   3. Elimina la clave 'escala' del JSON para mantener un único origen de verdad.
class AddScaleToProducts < ActiveRecord::Migration[8.0]
  def up
    add_column :products, :scale, :string unless column_exists?(:products, :scale)
    add_column :products, :show_scale_publicly, :boolean, default: true, null: false unless column_exists?(:products, :show_scale_publicly)
    add_index  :products, :scale unless index_exists?(:products, :scale)

    # Backfill: extraer escala del JSON de custom_attributes y limpiar la clave.
    say_with_time 'Backfilling product.scale from custom_attributes' do
      Product.reset_column_information
      backfilled = 0
      Product.where("custom_attributes ? 'escala'").find_each(batch_size: 200) do |product|
        attrs = product.custom_attributes.is_a?(Hash) ? product.custom_attributes.dup : {}
        value = attrs.delete('escala').presence
        next if value.blank? && product.scale.present?

        product.update_columns(
          scale: value,
          custom_attributes: attrs
        )
        backfilled += 1
      end
      backfilled
    end

    # Remover 'escala' del schema de atributos en CategoryAttributeTemplate:
    # ahora es columna de primer nivel, no custom attribute.
    say_with_time 'Removing escala key from CategoryAttributeTemplate.attributes_schema' do
      if defined?(CategoryAttributeTemplate)
        CategoryAttributeTemplate.find_each do |template|
          next unless template.attributes_schema.is_a?(Array)
          new_schema = template.attributes_schema.reject { |attr| attr.is_a?(Hash) && attr['key'].to_s == 'escala' }
          next if new_schema.size == template.attributes_schema.size

          template.update_columns(attributes_schema: new_schema, updated_at: Time.current)
        end
      end
    end
  end

  def down
    # Restaurar la clave 'escala' en custom_attributes para los productos que la tenían.
    Product.reset_column_information
    Product.where.not(scale: [nil, '']).find_each(batch_size: 200) do |product|
      attrs = product.custom_attributes.is_a?(Hash) ? product.custom_attributes.dup : {}
      attrs['escala'] = product.scale
      product.update_columns(custom_attributes: attrs)
    end

    remove_index  :products, :scale if index_exists?(:products, :scale)
    remove_column :products, :show_scale_publicly if column_exists?(:products, :show_scale_publicly)
    remove_column :products, :scale if column_exists?(:products, :scale)
  end
end
