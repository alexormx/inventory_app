# frozen_string_literal: true

class AddWhatsappCodeToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :whatsapp_code, :string
  end
end
