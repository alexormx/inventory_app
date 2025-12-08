# frozen_string_literal: true

class CreateVisitorLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :visitor_logs do |t|
      t.string :ip_address
      t.text :user_agent
      t.string :path

      t.timestamps
    end
  end
end
