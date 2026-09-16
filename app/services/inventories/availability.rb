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
      grouped_counts(Inventory.customer_available_now, product_ids, conditions: conditions)
    end

    # In-transit counts, same shape. Reservation is condition-specific too: a
    # CTA that submits one condition must never be authorized by another
    # condition's incoming supply.
    def self.in_transit_counts_for(product_ids, conditions: nil)
      grouped_counts(Inventory.customer_in_transit, product_ids, conditions: conditions)
    end

    # Earliest arrival per [product_id, condition], so a reservation label
    # shows the ETA of the condition it actually reserves - never a different
    # condition's date. Arrivals already in the past are ignored.
    def self.in_transit_etas_for(product_ids)
      ids = Array(product_ids).compact.uniq
      return {} if ids.empty?

      Inventory.customer_in_transit
               .where(product_id: ids)
               .joins(:purchase_order)
               .where.not(purchase_orders: { expected_delivery_date: nil })
               .where(purchase_orders: { expected_delivery_date: Date.current.. })
               .group(:product_id, :item_condition)
               .minimum('purchase_orders.expected_delivery_date')
               .each_with_object({}) do |((pid, cond), eta), acc|
        acc[[pid, normalize_condition(cond)]] = eta
      end
    end

    def self.grouped_counts(scope, product_ids, conditions: nil)
      ids = Array(product_ids).compact.uniq
      return {} if ids.empty?

      scope = scope.where(product_id: ids)
      scope = scope.where(item_condition: conditions) if conditions.present?
      scope.group(:product_id, :item_condition).count.each_with_object({}) do |((pid, cond), count), acc|
        acc[[pid, normalize_condition(cond)]] = count
      end
    end
    private_class_method :grouped_counts

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
