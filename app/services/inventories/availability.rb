# frozen_string_literal: true

module Inventories
  # Canonical storefront availability, shared by the catalog, product detail,
  # search/facets, related products, the WhatsApp list and the cart's stock
  # gate, so those surfaces can never disagree again.
  #
  # Two deliberately separate concepts:
  #
  #   available_now - physical, located, unallocated stock OF THIS CONDITION
  #                   (Inventory.customer_available_now). The only thing that
  #                   may authorize a normal "Agregar".
  #   in_transit    - already purchased, still arriving. Future availability,
  #                   surfaced for ETA/preorder UX, never as available now.
  #
  # Condition is part of availability identity: a product with one `mint`
  # piece has zero `brand_new` availability. Never aggregate by product alone
  # and then use that total to authorize a specific condition.
  #
  # Preorder/backorder stock is NOT modelled here — those flows have their own
  # semantics (Product#oversell_allowed?, InventoryServices::AvailabilitySplitter)
  # and are intentionally untouched.
  class Availability
    Result = Struct.new(:available_now, :in_transit, keyword_init: true) do
      def available_now?
        available_now.positive?
      end

      def in_transit?
        in_transit.positive?
      end
    end

    EMPTY = Result.new(available_now: 0, in_transit: 0).freeze

    def self.for(product, condition:)
      return EMPTY if product.nil? || condition.blank?

      new(product, condition).call
    end

    # Available-now counts for many products in one grouped query, keyed
    # [product_id, condition_name] - the catalog renders a card per product
    # and must not issue a query per card.
    def self.counts_for(product_ids, conditions: nil)
      ids = Array(product_ids).compact.uniq
      return {} if ids.empty?

      scope = Inventory.customer_available_now.where(product_id: ids)
      scope = scope.where(item_condition: conditions) if conditions.present?
      scope.group(:product_id, :item_condition).count.each_with_object({}) do |((pid, cond), count), acc|
        acc[[pid, normalize_condition(cond)]] = count
      end
    end

    # Grouping by an enum column can yield either the integer or the label
    # depending on how the column is read back; callers key on the label.
    def self.normalize_condition(value)
      return value if value.is_a?(String)

      Inventory.item_conditions.key(value) || value.to_s
    end

    def initialize(product, condition)
      @product = product
      @condition = condition.to_s
    end

    def call
      Result.new(available_now: count_for(Inventory.customer_available_now),
                 in_transit: count_for(Inventory.customer_in_transit))
    end

    private

    def count_for(scope)
      scope.where(product_id: @product.id).for_condition(@condition).count
    end
  end
end
