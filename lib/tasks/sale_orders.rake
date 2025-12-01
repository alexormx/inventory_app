# frozen_string_literal: true

namespace :sale_orders do
  desc 'Backfill total_tax and total_order_value for sale orders with zero/blank totals'
  task backfill_totals: :environment do
    scope = SaleOrder.where('total_order_value IS NULL OR total_order_value = 0')
    puts "Processing #{scope.count} sale orders…"
    scope.find_each(batch_size: 500) do |so|
      before = so.total_order_value
      so.valid? # triggers before_validation callbacks (compute_financials)
      puts "SO ##{so.id}: #{before.inspect} -> #{so.total_order_value}" if so.changed? && so.save(validate: false)
    end
    puts 'Done.'
  end
end
