# frozen_string_literal: true

class AddCostsDistributedAtToPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :purchase_orders, :costs_distributed_at, :datetime
    add_index :purchase_orders, :costs_distributed_at
  end
end
