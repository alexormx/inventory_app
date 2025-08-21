class MigrateAndDropLegacyRunTables < ActiveRecord::Migration[7.1]
  def up
    # Mover datos existentes a la tabla unificada
    if table_exists?(:maintenance_runs)
      if table_exists?(:inventory_status_sync_runs)
        execute <<~SQL
          INSERT INTO maintenance_runs (job_name, status, stats, started_at, finished_at, error, created_at, updated_at)
          SELECT 'inventories.reevaluate_statuses', status, stats, started_at, finished_at, error, created_at, updated_at
          FROM inventory_status_sync_runs
        SQL
      end

      if table_exists?(:sale_orders_backfill_runs)
        execute <<~SQL
          INSERT INTO maintenance_runs (job_name, status, stats, started_at, finished_at, error, created_at, updated_at)
          SELECT 'sale_orders.backfill_totals', status, stats, started_at, finished_at, error, created_at, updated_at
          FROM sale_orders_backfill_runs
        SQL
      end
    end

    drop_table :inventory_status_sync_runs, if_exists: true
    drop_table :sale_orders_backfill_runs, if_exists: true
  end

  def down
    # No recreamos tablas legacy; la migración es irreversible.
    raise ActiveRecord::IrreversibleMigration
  end
end
