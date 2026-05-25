# frozen_string_literal: true

class AddReferrerAndIndexesToVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_logs, :referrer, :string

    add_index :visitor_logs, :last_visited_at
    add_index :visitor_logs, :country
    add_index :visitor_logs, :path
  end
end
