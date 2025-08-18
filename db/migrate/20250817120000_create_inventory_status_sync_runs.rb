class CreateInventoryStatusSyncRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :inventory_status_sync_runs do |t|
      t.string :status, null: false, default: "queued"
      t.text :stats
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end
  end
end
