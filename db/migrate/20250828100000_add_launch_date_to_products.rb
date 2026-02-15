# frozen_string_literal: true

class AddLaunchDateToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :launch_date, :date
    add_index :products, :launch_date
  end
end
