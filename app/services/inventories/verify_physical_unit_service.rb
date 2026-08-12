# frozen_string_literal: true

module Inventories
  # Verifies one exact, currently unlocated Inventory row. Authorization is
  # enforced here because callers outside an Admin controller can invoke this
  # stock-changing service; the actor is also snapshotted in the audit event.
  class VerifyPhysicalUnitService
    class Error < StandardError; end
    class InvalidVerificationResult < Error; end
    class InvalidInventoryState < Error; end
    class InvalidLocation < Error; end
    class InvalidSnapshot < Error; end
    class ReservedInventoryRequiresReconciliation < Error; end
    class UnauthorizedActor < Error; end

    class StaleInventory < Error
      attr_reader :changed_fields

      def initialize(changed_fields)
        @changed_fields = changed_fields
        super("Inventory changed after it was displayed: #{changed_fields.join(', ')}")
      end
    end

    Result = Struct.new(:inventory, :event, keyword_init: true)

    SUPPORTED_RESULTS = InventoryEvent::PHYSICAL_VERIFICATION_RESULTS.freeze
    SUPPORTED_STATUSES = %w[available reserved].freeze
    SNAPSHOT_FIELDS = %w[
      updated_at
      status
      inventory_location_id
      sale_order_id
      sale_order_item_id
      product_id
    ].freeze

    def self.call(inventory_id:, result:, actor:, expected_snapshot:, location_id: nil, notes: nil)
      new(
        inventory_id: inventory_id,
        result: result,
        actor: actor,
        expected_snapshot: expected_snapshot,
        location_id: location_id,
        notes: notes
      ).call
    end

    # Future HTTP callers must use this builder rather than relying on Rails'
    # default millisecond JSON precision for updated_at.
    def self.snapshot_for(inventory)
      {
        updated_at: inventory.updated_at.utc.iso8601(6),
        status: inventory.status,
        inventory_location_id: inventory.inventory_location_id,
        sale_order_id: inventory.sale_order_id,
        sale_order_item_id: inventory.sale_order_item_id,
        product_id: inventory.product_id
      }
    end

    def initialize(inventory_id:, result:, actor:, expected_snapshot:, location_id: nil, notes: nil)
      @inventory_id = inventory_id
      @result = result.to_s
      @actor = actor
      @expected_snapshot = expected_snapshot
      @location_id = location_id
      @notes = notes.to_s.strip.presence
    end

    def call
      validate_request!

      Inventory.transaction do
        inventory = Inventory.lock.find(@inventory_id)
        validate_snapshot!(inventory)
        validate_inventory_state!(inventory)
        location = validated_location
        previous_state = audit_state(inventory)

        apply_verification!(inventory, location)
        inventory.save!

        event = create_event!(inventory, previous_state)
        Result.new(inventory: inventory, event: event)
      end
    end

    private

    def validate_request!
      raise InvalidVerificationResult, "Unsupported physical verification result: #{@result.presence || '(blank)'}" unless SUPPORTED_RESULTS.include?(@result)

      unless @actor.is_a?(User) && @actor.persisted? && !@actor.destroyed? && @actor.admin?
        raise UnauthorizedActor, 'Physical inventory verification requires a persisted admin actor.'
      end

      validate_snapshot_shape!
    end

    def validate_snapshot_shape!
      raise InvalidSnapshot, 'Expected snapshot must be a hash.' unless @expected_snapshot.respond_to?(:to_h)

      snapshot = @expected_snapshot.to_h.stringify_keys
      missing_fields = SNAPSHOT_FIELDS.reject { |field| snapshot.key?(field) }
      raise InvalidSnapshot, "Expected snapshot is missing: #{missing_fields.join(', ')}" if missing_fields.any?

      @normalized_expected_snapshot = normalize_snapshot(snapshot)
    rescue ArgumentError, TypeError => e
      raise InvalidSnapshot, "Expected snapshot is invalid: #{e.message}"
    end

    def validate_snapshot!(inventory)
      current_snapshot = normalize_snapshot(self.class.snapshot_for(inventory).stringify_keys)
      changed_fields = SNAPSHOT_FIELDS.reject do |field|
        current_snapshot.fetch(field) == @normalized_expected_snapshot.fetch(field)
      end
      raise StaleInventory, changed_fields if changed_fields.any?
    end

    def validate_inventory_state!(inventory)
      unless SUPPORTED_STATUSES.include?(inventory.status)
        raise InvalidInventoryState, "Inventory status #{inventory.status} cannot be physically verified by this service."
      end

      raise InvalidInventoryState, 'Inventory already has a physical location.' if inventory.inventory_location_id.present?

      if inventory.reserved? && @result != 'found'
        raise ReservedInventoryRequiresReconciliation,
              'Reserved inventory that is damaged or missing requires order-level reconciliation.'
      end
    end

    def validated_location
      if @result == 'found'
        validate_found_location!
      elsif @location_id.present?
        raise InvalidLocation, 'A location can only be supplied when the unit was found.'
      end
    end

    def validate_found_location!
      raise InvalidLocation, 'A physical location is required when the unit was found.' if @location_id.blank?

      location = InventoryLocation.lock.find_by(id: @location_id)
      raise InvalidLocation, 'Physical location does not exist.' unless location
      raise InvalidLocation, 'Physical location is inactive.' unless location.active?
      raise InvalidLocation, 'Physical location must be a final leaf location.' unless location.leaf?

      location
    end

    def apply_verification!(inventory, location)
      case @result
      when 'found'
        inventory.inventory_location = location
      when 'damaged'
        inventory.status = :damaged
      when 'missing'
        inventory.status = :lost
      end
    end

    def create_event!(inventory, previous_state)
      InventoryEvent.create!(
        inventory: inventory,
        product_id: inventory.product_id,
        event_type: 'physical_inventory_verification',
        previous_sale_order_id: previous_state.fetch('sale_order_id'),
        new_sale_order_id: inventory.sale_order_id,
        metadata: event_metadata(inventory, previous_state)
      )
    end

    def event_metadata(inventory, previous_state)
      {
        'result' => @result,
        'notes' => @notes,
        'actor_id' => @actor.id,
        'actor_email' => @actor.email,
        'actor_name' => @actor.name,
        'previous_status' => previous_state.fetch('status'),
        'new_status' => inventory.status,
        'previous_location_id' => previous_state.fetch('inventory_location_id'),
        'new_location_id' => inventory.inventory_location_id,
        'product_id' => inventory.product_id,
        'purchase_order_id' => inventory.purchase_order_id,
        'purchase_order_item_id' => inventory.purchase_order_item_id,
        'sale_order_id' => inventory.sale_order_id,
        'sale_order_item_id' => inventory.sale_order_item_id,
        'expected_updated_at' => @normalized_expected_snapshot.fetch('updated_at'),
        'verified_inventory_updated_at' => normalize_timestamp(inventory.updated_at)
      }
    end

    def audit_state(inventory)
      inventory.attributes.slice(
        'status',
        'inventory_location_id',
        'sale_order_id'
      )
    end

    def normalize_snapshot(snapshot)
      {
        'updated_at' => normalize_timestamp(snapshot.fetch('updated_at')),
        'status' => snapshot.fetch('status').to_s,
        'inventory_location_id' => normalize_id(snapshot.fetch('inventory_location_id')),
        'sale_order_id' => snapshot.fetch('sale_order_id').to_s.presence,
        'sale_order_item_id' => normalize_id(snapshot.fetch('sale_order_item_id')),
        'product_id' => normalize_id(snapshot.fetch('product_id'))
      }
    end

    def normalize_timestamp(value)
      time = value.respond_to?(:to_time) ? value.to_time : Time.iso8601(value.to_s)
      time.utc.iso8601(6)
    end

    def normalize_id(value)
      return if value.blank?

      Integer(value.to_s, 10)
    end
  end
end
