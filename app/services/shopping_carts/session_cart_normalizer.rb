# frozen_string_literal: true

module ShoppingCarts
  # Turns the already-decoded session[:cart] value into a deterministic,
  # canonical structure that can be hashed and imported.
  #
  # The live storefront shape (see app/models/cart.rb) is
  #   { "product_id" => { "condition" => quantity } }
  # plus the legacy flat form { "product_id" => quantity } that Cart#initialize
  # migrates to brand_new. Both are accepted here with the same semantics.
  #
  # Policy, in order of strictness:
  # - structurally malformed data (non-hash levels, unknown conditions,
  #   non-canonical ids, non-integer quantities, ambiguous duplicate keys)
  #   invalidates the WHOLE payload: nothing is partially importable;
  # - quantities <= 0 (or nil) mean "no line", exactly like Cart#build_items
  #   skips them, so they are dropped rather than rejected;
  # - quantities above the technical bound are rejected, never clamped.
  #
  # Pure: no DB access, no pricing, no inventory. The session is already
  # decoded by Rails, so nothing here deserializes untrusted bytes.
  class SessionCartNormalizer
    DIGEST_VERSION = 'v1'
    # Mirrors the shopping_cart_items_quantity_bounded check constraint.
    MAX_QUANTITY = 100_000
    # Half of the cart_session_imports_payload_bounded check (8192 bytes):
    # that constraint measures jsonb rendered as text, which is longer than
    # the compact JSON measured here, and a session cart is bounded by the
    # 4 KB cookie anyway.
    MAX_PAYLOAD_BYTES = 4_096

    CONDITIONS = Inventory::ITEM_CONDITIONS.keys.map(&:to_s).freeze
    CONDITION_ORDER = CONDITIONS.each_with_index.to_h.freeze
    CANONICAL_INTEGER = /\A(?:0|[1-9]\d*)\z/
    POSITIVE_INTEGER = /\A[1-9]\d*\z/

    Line = Data.define(:product_reference, :condition, :quantity)

    Result = Data.define(:lines, :payload, :digest, :errors) do
      delegate :empty?, to: :lines

      def valid?
        errors.empty?
      end
    end

    def self.call(raw)
      new(raw).call
    end

    def initialize(raw)
      @raw = raw
      @errors = []
    end

    def call
      lines = extract_lines
      return invalid if @errors.any?

      payload = canonical_payload(lines)
      json = JSON.generate(payload)
      if json.bytesize > MAX_PAYLOAD_BYTES
        @errors << "payload exceeds #{MAX_PAYLOAD_BYTES} bytes"
        return invalid
      end

      Result.new(lines: lines, payload: payload, digest: digest_for(json), errors: [])
    end

    private

    def invalid
      Result.new(lines: [], payload: {}, digest: nil, errors: @errors.uniq)
    end

    def digest_for(json)
      Digest::SHA256.hexdigest("#{DIGEST_VERSION}:#{json}")
    end

    def extract_lines
      return [] if @raw.nil?

      unless @raw.is_a?(Hash)
        @errors << 'cart is not a hash'
        return []
      end

      seen_products = {}
      lines = []
      @raw.each do |raw_product, raw_conditions|
        product_reference = canonical_product_reference(raw_product)
        next if product_reference.nil?

        if seen_products.key?(product_reference)
          @errors << "ambiguous duplicate product #{product_reference}"
          next
        end
        seen_products[product_reference] = true

        lines.concat(extract_conditions(product_reference, raw_conditions))
      end
      lines
    end

    def canonical_product_reference(raw)
      case raw
      when Integer
        return raw if raw.positive?
      when String, Symbol
        return raw.to_s.to_i if raw.to_s.match?(POSITIVE_INTEGER)
      end
      @errors << "malformed product id #{raw.inspect.first(40)}"
      nil
    end

    def extract_conditions(product_reference, raw_conditions)
      # Legacy flat format: { product_id => quantity } means brand_new.
      raw_conditions = { 'brand_new' => raw_conditions } unless raw_conditions.is_a?(Hash)

      seen = {}
      raw_conditions.filter_map do |raw_condition, raw_quantity|
        condition = canonical_condition(raw_condition)
        next if condition.nil?

        if seen.key?(condition)
          @errors << "ambiguous duplicate condition #{condition} for product #{product_reference}"
          next
        end
        seen[condition] = true

        quantity = canonical_quantity(raw_quantity, product_reference, condition)
        next if quantity.nil?

        Line.new(product_reference: product_reference, condition: condition, quantity: quantity)
      end
    end

    def canonical_condition(raw)
      condition = raw.to_s if raw.is_a?(String) || raw.is_a?(Symbol)
      return condition if condition && CONDITIONS.include?(condition)

      @errors << "unknown condition #{raw.inspect.first(40)}"
      nil
    end

    # nil / 0 / negative mean "no line" (Cart#build_items skips them). Anything
    # that is not unambiguously an integer is malformed: Ruby's to_i would
    # happily turn 2.7 or "2abc" into 2, and that is not a cart the customer
    # ever built.
    def canonical_quantity(raw, product_reference, condition)
      quantity =
        case raw
        when nil then 0
        when Integer then raw
        when String then raw.match?(CANONICAL_INTEGER) ? raw.to_i : malformed_quantity(raw, product_reference, condition)
        else malformed_quantity(raw, product_reference, condition)
        end
      return nil if quantity.nil? || quantity <= 0

      if quantity > MAX_QUANTITY
        @errors << "quantity #{quantity} for product #{product_reference}/#{condition} exceeds #{MAX_QUANTITY}"
        return nil
      end
      quantity
    end

    def malformed_quantity(raw, product_reference, condition)
      @errors << "malformed quantity #{raw.inspect.first(40)} for product #{product_reference}/#{condition}"
      nil
    end

    # Products ascending by id, conditions in Inventory::ITEM_CONDITIONS order,
    # string keys: the same logical cart always serializes identically
    # regardless of how the session hash happened to be built.
    def canonical_payload(lines)
      lines
        .group_by(&:product_reference)
        .sort_by { |product_reference, _| product_reference }
        .to_h do |product_reference, product_lines|
          conditions = product_lines
                       .sort_by { |line| CONDITION_ORDER.fetch(line.condition) }
                       .to_h { |line| [line.condition, line.quantity] }
          [product_reference.to_s, conditions]
        end
    end
  end
end
