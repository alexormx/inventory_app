# frozen_string_literal: true

class AddUniqueIndexToVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    add_index :visitor_logs, %i[ip_address path user_id], unique: true, name: 'index_visitor_logs_on_ip_path_user_id'
  end
end
