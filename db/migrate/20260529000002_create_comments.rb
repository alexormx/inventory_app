# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.references :post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :status, null: false, default: 0
      t.datetime :approved_at

      t.timestamps
    end

    add_index :comments, %i[post_id status]
    add_index :comments, :status
  end
end
