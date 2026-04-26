# frozen_string_literal: true

require 'csv'

module PurchaseOrders
  class ReceptionCsvParserService
    class ParseError < StandardError; end

    DEFAULT_CURRENCY = 'JPY'

    REQUIRED_COLUMNS = %w[item_code qty_shipped price].freeze

    def initialize(uploaded_file, default_currency: DEFAULT_CURRENCY)
      @uploaded_file = uploaded_file
      @default_currency = default_currency
    end

    def call
      raise ParseError, 'Adjunta un CSV para continuar.' if @uploaded_file.blank?

      data = read_file
      table = CSV.parse(data, headers: true, skip_blanks: true, strip: true)
      raise ParseError, 'El CSV está vacío.' if table.headers.compact.empty?

      header_index = build_header_index(table.headers)
      missing = REQUIRED_COLUMNS - header_index.keys
      raise ParseError, "Columnas faltantes: #{missing.join(', ')}" if missing.any?

      product_rows, totals_row = split_rows(table, header_index)
      aggregated = aggregate(product_rows)

      {
        document_currency: @default_currency,
        invoice_date: nil,
        invoice_number: extract_invoice_number,
        subtotal: totals_row[:subtotal],
        shipping_cost: totals_row[:shipping],
        other_cost: totals_row[:other],
        document_total: totals_row[:total],
        rows: aggregated,
        notes: ["Importado desde CSV: #{filename}"].compact
      }
    rescue CSV::MalformedCSVError => e
      raise ParseError, "CSV malformado: #{e.message}"
    end

    private

    def read_file
      path = @uploaded_file.respond_to?(:path) ? @uploaded_file.path : @uploaded_file.tempfile.path
      raw = File.binread(path)
      raw.sub(/\A\xEF\xBB\xBF/, '').force_encoding('UTF-8')
    end

    def build_header_index(headers)
      headers.each_with_index.with_object({}) do |(header, idx), hash|
        next if header.nil?

        key = header.to_s.strip.downcase.gsub(/\s+/, '_')
        hash[key] = idx
      end
    end

    def split_rows(table, idx)
      product_rows = []
      totals_row = { subtotal: nil, shipping: nil, other: nil, total: nil }
      capture_totals = false

      table.each do |csv_row|
        values = csv_row.fields
        first = values[idx['item_code']].to_s.strip

        if capture_totals
          totals_row = {
            subtotal: parse_decimal(values[0]),
            shipping: parse_decimal(values[1]),
            other: parse_decimal(values[2]),
            tax: parse_decimal(values[3]),
            total: parse_decimal(values[4])
          }
          break
        end

        if first.casecmp('merchandise').zero?
          capture_totals = true
          next
        end

        next if first.blank?

        qty = parse_quantity(values[idx['qty_shipped']])
        next if qty.nil? || qty <= 0

        product_rows << {
          supplier_product_code: first,
          product_name: values[idx['item_name']].to_s.strip.presence,
          barcode: normalize_barcode(idx['jancode'] && values[idx['jancode']]),
          quantity: qty,
          unit_cost: parse_decimal(values[idx['price']]),
          weight_gr: idx['weight'] ? parse_decimal(values[idx['weight']]) : nil,
          origin_country: idx['origin_country'] ? values[idx['origin_country']].to_s.strip.presence : nil,
          confidence: 1.0
        }
      end

      [product_rows, totals_row]
    end

    def aggregate(rows)
      rows.group_by { |r| [r[:supplier_product_code], r[:unit_cost]] }.map do |_, group|
        base = group.first.dup
        base[:quantity] = group.sum { |r| r[:quantity] }
        base
      end
    end

    def parse_quantity(value)
      v = value.to_s.gsub(/[^\d\.\-]/, '')
      return nil if v.blank?

      f = v.to_f
      f.positive? ? f.round : nil
    end

    def parse_decimal(value)
      return nil if value.nil?

      cleaned = value.to_s.gsub(/[^\d\.\-]/, '')
      return nil if cleaned.blank?

      BigDecimal(cleaned)
    rescue ArgumentError
      nil
    end

    def normalize_barcode(value)
      return nil if value.nil?

      barcode = value.to_s.strip
      barcode.presence
    end

    def extract_invoice_number
      name = filename.to_s
      m = name.match(/INVOICE\s+(\w+)/i) || name.match(/Inv[\s_]+(\w+)/i)
      m && m[1]
    end

    def filename
      @uploaded_file.respond_to?(:original_filename) ? @uploaded_file.original_filename : nil
    end
  end
end
