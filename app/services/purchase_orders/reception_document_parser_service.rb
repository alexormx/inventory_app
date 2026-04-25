# frozen_string_literal: true

require "base64"
require "json"
require "mini_magick"
require "tmpdir"

module PurchaseOrders
  class ReceptionDocumentParserService
    class ParseError < StandardError; end

    DEFAULT_MODEL = "gpt-4o-mini".freeze
    MAX_PDF_PAGES = 3

    def initialize(uploaded_file, client: OpenAI::Client.new, model: DEFAULT_MODEL)
      @uploaded_file = uploaded_file
      @client = client
      @model = model
    end

    def call
      raise ParseError, "Adjunta un PDF o imagen para continuar." if @uploaded_file.blank?

      response = @client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_content }
          ],
          temperature: 0.1,
          response_format: { type: "json_object" },
          max_tokens: 1800
        }
      )

      parse_response(response)
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise ParseError, "No se pudo procesar el PDF como imágenes: #{e.message}"
    rescue JSON::ParserError => e
      raise ParseError, "No se pudo interpretar la respuesta del OCR: #{e.message}"
    rescue StandardError => e
      raise ParseError, "No se pudo extraer el documento: #{e.message}"
    end

    private

    def system_prompt
      <<~PROMPT
        Extrae filas de productos y metadatos de un documento de compra.
        Responde solo JSON con esta forma:
        {
          "document_currency": "JPY",
          "invoice_date": "2026-01-13",
          "invoice_number": "2186307",
          "subtotal": 74202,
          "shipping_cost": 7858,
          "other_cost": 2462,
          "document_total": 84522,
          "rows": [
            {
              "supplier_product_code": "TMT33336",
              "product_name": "LV-N Ferrari F40 (1989) (Red)",
              "quantity": 2,
              "unit_cost": 6224,
              "confidence": 0.98
            }
          ],
          "notes": ["texto breve"]
        }

        Reglas:
        - En invoices de HobbyLink Japan, el supplier_product_code suele ser el primer token dentro de la columna Description.
        - Ejemplo real: "TMT33336 LV-N Ferrari F40 (1989) (Red)" -> supplier_product_code = "TMT33336" y product_name = "LV-N Ferrari F40 (1989) (Red)".
        - quantity debe ser entero positivo. Si no aparece y la fila parece válida, usa 1.
        - unit_cost debe ser numérico sin símbolos de moneda. Si no existe, usa null.
        - Extrae subtotal, freight como shipping_cost, y payment processing fee u otros cargos similares como other_cost.
        - document_total debe ser el total final del invoice.
        - invoice_date debe venir en formato ISO YYYY-MM-DD cuando sea visible.
        - No inventes filas. Conserva el supplier_product_code exactamente como aparece.
        - Ignora dirección de envío y otros textos no relacionados con líneas comprables o cargos del invoice.
      PROMPT
    end

    def user_content
      [
        { type: "text", text: "Extrae las líneas comprables del documento adjunto." },
        *document_parts
      ]
    end

    def document_parts
      if pdf?
        pdf_page_data_urls.map do |data_url|
          { type: "image_url", image_url: { url: data_url } }
        end
      else
        [{ type: "image_url", image_url: { url: file_data_url(file_path, detected_content_type) } }]
      end
    end

    def pdf?
      detected_content_type == "application/pdf"
    end

    def parse_response(response)
      content = response.dig("choices", 0, "message", "content")
      raise ParseError, "El OCR no devolvió contenido utilizable." if content.blank?

      payload = JSON.parse(content)
      rows = Array(payload["rows"]).filter_map do |row|
        supplier_product_code = row["supplier_product_code"].to_s.strip.presence
        next if supplier_product_code.blank?

        {
          supplier_product_code: supplier_product_code,
          product_name: row["product_name"].to_s.strip.presence,
          quantity: normalize_quantity(row["quantity"]),
          unit_cost: normalize_decimal(row["unit_cost"]),
          confidence: row["confidence"].to_f
        }
      end

      raise ParseError, "No se detectaron líneas de producto en el documento." if rows.empty?

      {
        document_currency: payload["document_currency"].to_s.upcase.presence,
        invoice_date: normalize_date(payload["invoice_date"]),
        invoice_number: payload["invoice_number"].to_s.strip.presence,
        subtotal: normalize_decimal(payload["subtotal"]),
        shipping_cost: normalize_decimal(payload["shipping_cost"]),
        other_cost: normalize_decimal(payload["other_cost"]),
        document_total: normalize_decimal(payload["document_total"]),
        rows: rows,
        notes: Array(payload["notes"]).map(&:to_s).map(&:strip).reject(&:blank?)
      }
    end

    def normalize_quantity(value)
      quantity = value.to_i
      quantity.positive? ? quantity : 1
    end

    def normalize_decimal(value)
      return nil if value.nil? || value.to_s.strip.blank?

      BigDecimal(value.to_s.gsub(/[^\d\.\-]/, ""))
    rescue ArgumentError
      nil
    end

    def normalize_date(value)
      return nil if value.to_s.strip.blank?

      Date.parse(value.to_s).iso8601
    rescue Date::Error, ArgumentError
      nil
    end

    def pdf_page_data_urls
      Dir.mktmpdir("po-reception-pdf") do |dir|
        MiniMagick::Tool::Convert.new do |convert|
          convert.density("220")
          convert << "#{file_path}[0-#{MAX_PDF_PAGES - 1}]"
          convert << File.join(dir, "page-%02d.png")
        end

        paths = Dir[File.join(dir, "page-*.png")].sort
        raise ParseError, "No se pudieron generar vistas del PDF para OCR." if paths.empty?

        paths.map { |path| file_data_url(path, "image/png") }
      end
    end

    def file_data_url(path, content_type)
      encoded = Base64.strict_encode64(File.binread(path))
      "data:#{content_type};base64,#{encoded}"
    end

    def detected_content_type
      @detected_content_type ||= @uploaded_file.content_type.to_s.presence || "application/octet-stream"
    end

    def file_path
      @file_path ||= @uploaded_file.respond_to?(:path) ? @uploaded_file.path : @uploaded_file.tempfile.path
    end
  end
end