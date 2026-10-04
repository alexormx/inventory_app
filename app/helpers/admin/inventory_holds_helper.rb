# frozen_string_literal: true

module Admin
  # Reads a physical unit's active cart hold for the admin UI.
  #
  # CartInventoryHold.active stays the single definition of "active", so an
  # expired hold shows nothing whether or not cleanup has removed its row.
  # The association is preloaded by the controller, so this costs no query
  # per row; `loaded?` keeps it honest if a caller ever forgets.
  module InventoryHoldsHelper
    def active_cart_hold_for(item)
      hold = if item.association(:cart_inventory_hold).loaded?
               item.cart_inventory_hold
             else
               CartInventoryHold.find_by(inventory_id: item.id)
             end

      hold if hold&.active?
    end
  end
end
