# frozen_string_literal: true

class AddAccountFieldsToPaymentMethods < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_methods, :account_number, :string
    add_column :payment_methods, :account_holder, :string
    add_column :payment_methods, :bank_name, :string
  end
end
