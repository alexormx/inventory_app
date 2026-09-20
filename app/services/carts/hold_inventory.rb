# frozen_string_literal: true

module Carts
  # Reconciles a cart line's CartInventoryHold rows against the quantity the
  # customer actually wants, claiming exact physical Inventory rows.
  #
  # Holds are OPPORTUNISTIC by design: a line may legitimately hold fewer rows
  # than its quantity, because preorder and backorder quantities have no
  # physical unit to claim yet. A partial claim is reported, never an error,
  # so the cart keeps behaving exactly as it does today.
  #
  # Exclusivity is decided by PostgreSQL, never by a read-then-write check in
  # Ruby. Each claim is one atomic statement against the UNIQUE(inventory_id)
  # index:
  #
  #   INSERT ... ON CONFLICT (inventory_id) DO UPDATE
  #     SET ... WHERE cart_inventory_holds.expires_at <= clock_timestamp()
  #     RETURNING id
  #
  # A free row inserts. A row whose hold has expired is reclaimed in place by
  # the DO UPDATE. A row still actively held by anyone fails the WHERE, returns
  # no id, and this service moves on to the next candidate. Two carts racing
  # for the same unit therefore cannot both win: the loser simply gets nothing
  # back and tries elsewhere.
  class HoldInventory
    Result = Struct.new(:held, :requested, :inventory_ids, keyword_init: true) do
      def complete?
        held >= requested
      end
    end

    # Brings the line to `target_quantity` holds: preserves the valid ones it
    # already has, claims only the shortfall, releases only the excess.
    def self.sync(cart:, cart_item:, product:, condition:, target_quantity:)
      new(cart: cart, cart_item: cart_item, product: product, condition: condition).sync(target_quantity)
    end

    # Normal release path for a line that is going away or shrinking to zero.
    # Rows are deleted, never left behind with a live expiry and a null line.
    def self.release_all(cart_item:)
      return 0 if cart_item.nil?

      CartInventoryHold.for_cart_item(cart_item).delete_all
    end

    def initialize(cart:, cart_item:, product:, condition:)
      @cart = cart
      @cart_item = cart_item
      @product = product
      @condition = Inventories::Availability.normalize_condition(condition)
    end

    def sync(target_quantity)
      target = target_quantity.to_i
      return Result.new(held: 0, requested: 0, inventory_ids: []) if target <= 0 && release_everything

      current = active_hold_ids
      if current.size > target
        release_excess(current, current.size - target)
      elsif current.size < target
        claim(target - current.size)
      end

      final = active_hold_ids
      Result.new(held: final.size, requested: target, inventory_ids: final)
    end

    private

    def release_everything
      self.class.release_all(cart_item: @cart_item)
      true
    end

    def active_hold_ids
      CartInventoryHold.active.for_cart_item(@cart_item).order(:id).pluck(:inventory_id)
    end

    # Deterministic: the most recently claimed rows go first, so the units the
    # customer has held longest are the ones kept.
    def release_excess(_current, count)
      doomed = CartInventoryHold.active.for_cart_item(@cart_item).order(id: :desc).limit(count).pluck(:id)
      CartInventoryHold.where(id: doomed).delete_all
    end

    def claim(count)
      candidates(count).each do |inventory_id|
        break if count <= 0

        count -= 1 if claim_one(inventory_id)
      end
    end

    # Eligible physical units of THIS condition that nobody currently holds.
    # Mirrors InventoryServices::ReserveSaleOrderItem's ordering so a cart
    # claims the same rows checkout would otherwise have picked.
    def candidates(count)
      available_status = Inventory.statuses.fetch('available')
      Inventory.customer_sellable
               .where(product_id: @product.id, item_condition: @condition)
               .where.not(id: CartInventoryHold.active.select(:inventory_id))
               .order(
                 Arel.sql("CASE WHEN status = #{available_status} THEN 0 ELSE 1 END"),
                 :created_at,
                 :id
               )
               .limit(count * CANDIDATE_OVERSCAN)
               .pluck(:id)
    end

    # Fetch a few more candidates than strictly needed so a lost race still has
    # somewhere to go without a second round trip.
    CANDIDATE_OVERSCAN = 3

    def claim_one(inventory_id)
      sql = <<~SQL.squish
        INSERT INTO cart_inventory_holds
          (inventory_id, shopping_cart_id, shopping_cart_item_id, expires_at, created_at, updated_at)
        VALUES
          (:inventory_id, :cart_id, :cart_item_id,
           clock_timestamp() + (:hold_seconds * INTERVAL '1 second'),
           clock_timestamp(), clock_timestamp())
        ON CONFLICT (inventory_id) DO UPDATE
          SET shopping_cart_id      = EXCLUDED.shopping_cart_id,
              shopping_cart_item_id = EXCLUDED.shopping_cart_item_id,
              expires_at            = EXCLUDED.expires_at,
              updated_at            = EXCLUDED.updated_at
          WHERE cart_inventory_holds.expires_at <= clock_timestamp()
        RETURNING id
      SQL

      bound = CartInventoryHold.sanitize_sql_array([
                                                     sql,
                                                     {
                                                       inventory_id: inventory_id,
                                                       cart_id: @cart.id,
                                                       cart_item_id: @cart_item&.id,
                                                       hold_seconds: CartInventoryHold::HOLD_DURATION.to_i
                                                     }
                                                   ])
      CartInventoryHold.connection.exec_query(bound, 'CartInventoryHold Claim').rows.any?
    end
  end
end
