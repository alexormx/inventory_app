# frozen_string_literal: true

module Inventories
  # Refuses an admin mutation that would take a physical unit away from the
  # customer whose cart is actively holding it.
  #
  # This does NOT change how holds work. CartInventoryHold remains the sole
  # authority for temporary cart ownership, `Inventory.status` keeps meaning
  # physical/commercial state only, and CartInventoryHold.active stays the one
  # definition of "active" - an expired hold blocks nothing, whether or not
  # the cleanup job has removed its row.
  #
  # Concurrency follows PR #184: the physical Inventory row is the
  # serialization point. The row is locked FOR UPDATE and hold ownership is
  # re-read *under that lock*, so an admin cannot squeeze a mutation in
  # between a cart's claim and its commit. Only the Inventory row is locked
  # here - never Product or ShoppingCart - so no new lock-order cycle appears.
  class HoldProtection
    # Transitions that would steal or destroy a unit a customer is holding.
    # `reserved` counts: manually allocating the piece to another order takes
    # it just as surely as scrapping it does.
    PROTECTED_STATUSES = %w[reserved damaged lost scrap marketing].freeze

    Result = Struct.new(:performed, :hold, :reason, keyword_init: true) do
      def performed?
        performed
      end

      def blocked?
        !performed
      end

      # Refused because a customer's cart owns the unit, as opposed to
      # refused because the caller itself rejected the change.
      def held?
        hold.present?
      end
    end

    def self.protected_status?(status)
      PROTECTED_STATUSES.include?(status.to_s)
    end

    # Locks the row, re-checks ownership, and only then yields it. The block
    # receives the LOCKED record, so callers validate and mutate the row they
    # actually verified rather than a stale copy read before the lock.
    #
    # A block returning `false` aborts without treating it as a hold refusal,
    # which lets callers run their own preconditions (a status-transition
    # allow-list, say) against the locked state instead of a stale one.
    def self.guard(inventory_id)
      result = nil

      Inventory.transaction do
        locked = Inventory.lock.find_by(id: inventory_id)
        next result = Result.new(performed: false, hold: nil, reason: :missing) if locked.nil?

        hold = CartInventoryHold.active.find_by(inventory_id: locked.id)
        next result = Result.new(performed: false, hold: hold, reason: :held) if hold

        next result = Result.new(performed: false, hold: nil, reason: :rejected) if yield(locked) == false

        result = Result.new(performed: true, hold: nil, reason: nil)
      end

      result
    end
  end
end
