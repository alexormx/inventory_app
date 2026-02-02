# frozen_string_literal: true

module Products
  # Service to discontinue a product and convert all 'new' inventory to 'misb'
  # with a new price. Also supports reversing the process.
  class DiscontinueService
    attr_reader :product, :errors

    def initialize(product)
      @product = product
      @errors = []
    end

    # Discontinue the product: mark as discontinued and convert inventory
    # @param misb_price [Decimal] Price to set for MISB items
    # @return [Hash] { converted_count: N } or raises error
    def discontinue!(misb_price:)
      raise ArgumentError, 'El producto ya está descontinuado' if product.discontinued?
      raise ArgumentError, 'Debe especificar un precio válido para las piezas MISB' if misb_price.blank? || misb_price <= 0

      ActiveRecord::Base.transaction do
        # Update all 'new' inventory items to 'misb' with the new price
        affected_count = convert_inventory_to_misb(misb_price)

        # Mark product as discontinued
        product.update!(discontinued: true)

        Rails.logger.info "[DiscontinueService] Product #{product.id} discontinued. #{affected_count} inventory items converted to MISB at $#{misb_price}"

        { converted_count: affected_count }
      end
    end

    # Reverse the discontinuation: unmark and convert inventory back to 'new'
    # @param new_price [Decimal, nil] Optional price to set (nil clears individual price)
    # @return [Hash] { converted_count: N } or raises error
    def reverse!(new_price: nil)
      raise ArgumentError, 'El producto no está descontinuado' unless product.discontinued?

      ActiveRecord::Base.transaction do
        # Update all 'misb' inventory items back to 'new'
        affected_count = convert_inventory_to_new(new_price)

        # Unmark product as discontinued
        product.update!(discontinued: false)

        Rails.logger.info "[DiscontinueService] Product #{product.id} restored. #{affected_count} inventory items converted to NEW"

        { converted_count: affected_count }
      end
    end

    private

    def convert_inventory_to_misb(price)
      # Only convert inventory that is 'brand_new' and available/reserved (in stock)
      inventory_scope = product.inventories.where(item_condition: :brand_new)
                               .where(status: %w[available reserved in_transit])

      count = inventory_scope.count

      inventory_scope.find_each do |inventory|
        inventory.update!(
          item_condition: :misb,
          selling_price: price
        )
      end

      count
    end

    def convert_inventory_to_new(price)
      # Only convert inventory that is 'misb' (was converted from brand_new)
      inventory_scope = product.inventories.where(item_condition: :misb)
                               .where(status: %w[available reserved in_transit])

      count = inventory_scope.count

      inventory_scope.find_each do |inventory|
        # Clear the individual selling_price so it uses product price
        inventory.update!(
          item_condition: :brand_new,
          selling_price: price
        )
      end

      count
    end
  end
end
