# frozen_string_literal: true

class AddEditorModeToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :editor_mode, :integer, null: false, default: 0
  end
end
