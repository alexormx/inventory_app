class CreateCategoryAttributeTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :category_attribute_templates do |t|
      t.string :category, null: false
      t.jsonb :attributes_schema, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :category_attribute_templates, :category, unique: true
    add_index :category_attribute_templates, :active
  end
end
