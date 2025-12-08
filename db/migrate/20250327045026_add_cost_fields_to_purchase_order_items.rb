# frozen_string_literal: true

class AddCostFieldsToPurchaseOrderItems < ActiveRecord::Migration[8.0]
  def up
    #Add unit_additional_cost, unit_compose_cost, unit_compose_cost_in_mxn, total_line_volume, total_line_cost, total_line_cost_in_mxn to purchase_order_items
    add_column :purchase_order_items, :unit_additional_cost, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :unit_compose_cost, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :unit_compose_cost_in_mxn, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :total_line_volume, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :total_line_weight, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :total_line_cost, :decimal, precision: 10, scale: 2
    add_column :purchase_order_items, :total_line_cost_in_mxn, :decimal, precision: 10, scale: 2
  end

  def down
    # Remove unit_additional_cost, unit_compose_cost, unit_compose_cost_in_mxn, total_line_volume, total_line_cost, total_line_cost_in_mxn from purchase_order_items
    remove_column :purchase_order_items, :unit_additional_cost
    remove_column :purchase_order_items, :unit_compose_cost
    remove_column :purchase_order_items, :unit_compose_cost_in_mxn
    remove_column :purchase_order_items, :total_line_volume
    remove_column :purchase_order_items, :total_line_weight
    remove_column :purchase_order_items, :total_line_cost
    remove_column :purchase_order_items, :total_line_cost_in_mxn
  end
end
