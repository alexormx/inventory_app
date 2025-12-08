# frozen_string_literal: true

class AddCurrencyAndExchangeRateToPurchaseOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :purchase_orders, :currency, :string, null: false, default: 'MXN'
    add_column :purchase_orders, :exchange_rate, :decimal, precision: 10, scale: 4, null: false, default: 1.0
  end

  def down
    remove_column :purchase_orders, :currency
    remove_column :purchase_orders, :exchange_rate
  end
end
