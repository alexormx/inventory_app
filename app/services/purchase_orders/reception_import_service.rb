# frozen_string_literal: true

module PurchaseOrders
  class ReceptionImportService
    class ImportError < StandardError; end

    Result = Struct.new(:purchase_order, :resolved_rows, :unresolved_rows, keyword_init: true)

    VALID_ACTIONS = %w[use_existing sync_catalog import_hlj skip].freeze

    def initialize(user:, decisions:, document_metadata: {}, order_date: nil, expected_delivery_date: nil,
                   status: "Pending", currency: nil, exchange_rate: nil, notes: nil,
                   uploaded_filename: nil, hlj_lookup: nil)
      @user = user
      @decisions = Array(decisions)
      @document_metadata = document_metadata || {}
      @order_date = order_date
      @expected_delivery_date = expected_delivery_date
      @status = status.presence || "Pending"
      @currency = currency.presence
      @exchange_rate = exchange_rate
      @notes = notes.to_s.strip
      @uploaded_filename = uploaded_filename
      @hlj_lookup = hlj_lookup || ->(code) { Suppliers::Hlj::ImportBySupplierCodeService.new(code).call }
    end

    def call
      resolved_rows = []
      unresolved_rows = []

      ActiveRecord::Base.transaction do
        @decisions.each do |decision|
          action = decision[:action].to_s
          unless VALID_ACTIONS.include?(action)
            unresolved_rows << decision.merge(reason: "Acción inválida: #{decision[:action]}")
            next
          end
          next if action == "skip"

          product = resolve_product(decision)
          if product
            resolved_rows << decision.merge(product: product, action: action)
          else
            unresolved_rows << decision.merge(reason: "No se pudo materializar producto para #{decision[:supplier_product_code]}")
          end
        end

        raise ImportError, "No se pudo resolver ningún producto del documento." if resolved_rows.empty?

        purchase_order = build_purchase_order(resolved_rows, unresolved_rows)
        purchase_order.save!
        Result.new(purchase_order: purchase_order, resolved_rows: resolved_rows, unresolved_rows: unresolved_rows)
      end
    rescue ActiveRecord::RecordInvalid => e
      raise ImportError, e.record.errors.full_messages.to_sentence
    end

    private

    def resolve_product(decision)
      case decision[:action].to_s
      when "use_existing"
        Product.find_by(id: decision[:product_id])
      when "sync_catalog"
        catalog_item = SupplierCatalogItem.find_by(id: decision[:catalog_item_id])
        return nil unless catalog_item

        Suppliers::Catalog::SyncProductService.new(catalog_item).call.product
      when "import_hlj"
        code = decision[:supplier_product_code].to_s.strip
        return nil if code.blank?

        catalog_item = @hlj_lookup.call(code)
        return nil unless catalog_item

        Suppliers::Catalog::SyncProductService.new(catalog_item).call.product
      end
    end

    def build_purchase_order(resolved_rows, unresolved_rows)
      purchase_order = PurchaseOrder.new(
        user: @user,
        order_date: resolved_order_date,
        expected_delivery_date: @expected_delivery_date,
        status: @status,
        currency: resolved_currency(@document_metadata[:document_currency]),
        exchange_rate: normalized_exchange_rate,
        shipping_cost: @document_metadata[:shipping_cost] || 0,
        tax_cost: 0,
        other_cost: @document_metadata[:other_cost] || 0,
        subtotal: 0,
        total_order_cost: 0,
        total_cost_mxn: 0,
        notes: composed_notes(resolved_rows, unresolved_rows)
      )

      resolved_rows.each do |row|
        purchase_order.purchase_order_items.build(
          product: row[:product],
          quantity: row[:quantity].to_i.positive? ? row[:quantity].to_i : 1,
          unit_cost: row[:unit_cost] || 0
        )
      end

      purchase_order
    end

    def resolved_currency(parsed_currency)
      candidate = parsed_currency.presence || @currency || "JPY"
      PurchaseOrder::CURRENCIES.include?(candidate) ? candidate : (@currency || "JPY")
    end

    def resolved_order_date
      return @order_date if @order_date.present?
      return Date.parse(@document_metadata[:invoice_date]) if @document_metadata[:invoice_date].present?

      Date.current
    rescue Date::Error, ArgumentError
      @order_date.presence || Date.current
    end

    def normalized_exchange_rate
      value = @exchange_rate.presence || 1
      BigDecimal(value.to_s)
    rescue ArgumentError
      1
    end

    def composed_notes(resolved_rows, unresolved_rows)
      segments = []
      segments << @notes if @notes.present?
      segments << "Documento importado: #{@uploaded_filename}" if @uploaded_filename.present?
      segments << "Invoice #: #{@document_metadata[:invoice_number]}" if @document_metadata[:invoice_number].present?
      segments << "Líneas resueltas: #{resolved_rows.map { |row| row[:supplier_product_code] }.join(', ')}"
      if unresolved_rows.any?
        segments << "Líneas no resueltas: #{unresolved_rows.map { |row| row[:supplier_product_code] }.join(', ')}"
      end
      segments.concat(Array(@document_metadata[:notes]))
      segments.reject(&:blank?).join("\n")
    end
  end
end
