class AddSeoFieldsToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :highlights, :text, default: "[]"
    add_column :products, :seo_keywords, :text, default: "[]"
  end
end
