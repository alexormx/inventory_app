# frozen_string_literal: true

class AddCreditFieldsToUsersAndSaleOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :credit_enabled, :boolean, default: false, null: false
    add_column :users, :default_credit_terms, :string, default: 'none', null: false
    add_column :users, :credit_limit, :decimal, precision: 12, scale: 2

    add_index :users, :credit_enabled
    add_index :users, :default_credit_terms

    add_column :sale_orders, :credit_override, :boolean, default: false, null: false
    add_column :sale_orders, :credit_terms, :string
    add_column :sale_orders, :due_date, :date

    add_index :sale_orders, :credit_override
    add_index :sale_orders, :due_date
  end
end
