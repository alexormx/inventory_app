# frozen_string_literal: true

class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :rating, null: false
      t.string :title
      t.text :body, null: false
      t.integer :status, null: false, default: 0
      t.boolean :verified_purchase, null: false, default: false
      t.datetime :approved_at

      t.timestamps
    end

    add_index :reviews, %i[product_id user_id], unique: true
    add_index :reviews, %i[product_id status]
    add_index :reviews, :status
  end
end
