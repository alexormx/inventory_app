# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :excerpt
      t.text :meta_description
      t.integer :status, null: false, default: 0
      t.datetime :published_at

      t.timestamps
    end

    add_index :posts, :slug, unique: true
    add_index :posts, :status
    add_index :posts, :published_at
  end
end
