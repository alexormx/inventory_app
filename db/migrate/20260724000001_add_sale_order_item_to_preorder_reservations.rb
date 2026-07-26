# frozen_string_literal: true

class AddSaleOrderItemToPreorderReservations < ActiveRecord::Migration[8.0]
  def change
    # Existing reservations remain unverified rather than inferring a line from
    # product/order data that may be ambiguous.
    add_reference :preorder_reservations,
                  :sale_order_item,
                  null: true,
                  foreign_key: true,
                  index: true
  end
end
