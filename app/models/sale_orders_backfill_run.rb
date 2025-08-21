class SaleOrdersBackfillRun < ApplicationRecord
	# DEPRECADO: Reemplazado por MaintenanceRun (job_name = 'sale_orders.backfill_totals').
	# Se mantiene una clase abstracta para no romper autoload/eager load.
	self.abstract_class = true
end
