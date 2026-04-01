class AddPrimaryProductImageAttachmentIdToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :primary_product_image_attachment_id, :bigint
    add_index :products, :primary_product_image_attachment_id
  end
end