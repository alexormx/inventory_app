# frozen_string_literal: true

class CreateSystemVariables < ActiveRecord::Migration[8.0]
  def change
    create_table :system_variables do |t|
      t.string :name, null: false
      t.string :value
      t.string :description
      t.timestamps
    end
    add_index :system_variables, :name, unique: true
  end
end
