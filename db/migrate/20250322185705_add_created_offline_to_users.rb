# frozen_string_literal: true

class AddCreatedOfflineToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :created_offline, :boolean
  end

  def down
    remove_column :users, :created_offline
  end
end
