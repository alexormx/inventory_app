class AddUserToVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :visitor_logs, :user, null: true, foreign_key: true
  end
end
