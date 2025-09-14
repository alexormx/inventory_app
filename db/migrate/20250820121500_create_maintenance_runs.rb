# frozen_string_literal: true

class CreateMaintenanceRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :maintenance_runs do |t|
      t.string :job_name, null: false
      t.string :status, null: false, default: 'queued'
      t.text :stats
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end

    add_index :maintenance_runs, :job_name
    add_index :maintenance_runs, :status
    add_index :maintenance_runs, :created_at
  end
end
