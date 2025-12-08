# frozen_string_literal: true

namespace :products do
  desc 'Recompute product stats (purchase/sales/derived) for all products'
  task recompute_stats: :environment do
    puts 'Recomputing product stats...'
    total = Product.count
    processed = 0
    Product.find_each(batch_size: 200) do |product|
      Products::UpdateStatsService.new(product).call
      processed += 1
      puts "Processed #{processed}/#{total}: #{product.try(:sku) || product.id}" if (processed % 100).zero?
    end
    puts "Done. #{processed} products updated."
  end
end
