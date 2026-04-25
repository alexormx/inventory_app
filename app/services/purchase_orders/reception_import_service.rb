# frozen_string_literal: true

module PurchaseOrders
  class ReceptionImportService
    class ImportError < StandardError; end

    Result = Struct.new(:purchase_order, :resolved_rows, :unresolved_rows, keyword_init: true)

    def initialize(user:, uploaded_file:, order_date:, expected_delivery_date:, status: "Pending", currency: nil,
                   exchange_rate: nil, notes: nil, parser: nil, resolver: nil)
      @user = user
      @uploaded_file = uploaded_file
      @order_date = order_date
      @expected_delivery_date = expected_delivery_date
      @status = status.presence || "Pending"
      @currency = currency.presence
      @exchange_rate = exchange_rate
      @notes = notes.to_s.strip
      @parser = parser || PurchaseOrders::ReceptionDocumentParserService.new(@uploaded_file)
      @resolver = resolver
    end

    def call
      parsed = @parser.call
      resolved_rows = []
      unresolved_rows = []

      Array(parsed[:rows]).each do |row|
        resolution = resolve_row(row)
        if resolution&.product.present?
          resolved_rows << row.merge(product: resolution.product, source: resolution.source)
        else
          unresolved_rows << row.merge(reason: "No se encontró producto para Supplier ID #{row[:supplier_product_code]}")
        end
      end

      raise ImportError, "No se pudo resolver ningún producto del documento." if resolved_rows.empty?

      purchase_order = build_purchase_order(parsed, resolved_rows, unresolved_rows)
      purchase_order.save!

      Result.new(purchase_order: purchase_order, resolved_rows: resolved_rows, unresolved_rows: unresolved_rows)
    rescue ActiveRecord::RecordInvalid => e
      raise ImportError, e.record.errors.full_messages.to_sentence
    end

    private

    def resolve_row(row)
      return @resolver.call(row) if @resolver.respond_to?(:call)

      PurchaseOrders::ReceptionProductResolverService.new(row[:supplier_product_code]).call
    end

    def build_purchase_order(parsed, resolved_rows, unresolved_rows)
      purchase_order = PurchaseOrder.new(
        user: @user,
        order_date: resolved_order_date(parsed),
        expected_delivery_date: @expected_delivery_date,
        status: @status,
        currency: resolved_currency(parsed[:document_currency]),
        exchange_rate: normalized_exchange_rate,
        shipping_cost: parsed[:shipping_cost] || 0,
        tax_cost: 0,
        other_cost: parsed[:other_cost] || 0,
        subtotal: 0,
        total_order_cost: 0,
        total_cost_mxn: 0,
        notes: composed_notes(parsed, resolved_rows, unresolved_rows)
      )

      resolved_rows.each do |row|
        purchase_order.purchase_order_items.build(
          product: row[:product],
          quantity: row[:quantity],
          unit_cost: row[:unit_cost] || 0
        )
      end

      purchase_order
    end

    def resolved_currency(parsed_currency)
      candidate = parsed_currency.presence || @currency || "JPY"
      PurchaseOrder::CURRENCIES.include?(candidate) ? candidate : (@currency || "JPY")
    end

    def resolved_order_date(parsed)
      return @order_date if @order_date.present?
      return Date.parse(parsed[:invoice_date]) if parsed[:invoice_date].present?

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

    def composed_notes(parsed, resolved_rows, unresolved_rows)
      segments = []
      segments << @notes if @notes.present?
      segments << "Documento importado: #{@uploaded_file.original_filename}" if @uploaded_file.respond_to?(:original_filename)
      segments << "Invoice #: #{parsed[:invoice_number]}" if parsed[:invoice_number].present?
      segments << "Líneas resueltas: #{resolved_rows.map { |row| row[:supplier_product_code] }.join(', ')}"
      if unresolved_rows.any?
        segments << "Líneas no resueltas: #{unresolved_rows.map { |row| row[:supplier_product_code] }.join(', ')}"
      end
      segments.concat(Array(parsed[:notes]))
      segments.reject(&:blank?).join("\n")
    end
  end
end