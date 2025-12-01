# frozen_string_literal: true

class AddTrackingToVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_logs, :visit_count, :integer
    add_column :visitor_logs, :last_visited_at, :datetime
  end
end
