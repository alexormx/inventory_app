module Sepomex
  class Importer
    # Expect CSV with headers: cp,state,municipality,settlement,settlement_type
    def initialize(path, logger: Rails.logger)
      @path = path
      @logger = logger
    end

    def call
      raise ArgumentError, "File not found: #{@path}" unless File.exist?(@path)
      require 'csv'
      batch = []
      inserted = 0
      CSV.foreach(@path, headers: true) do |row|
        attrs = normalize_row(row.to_h)
        next unless valid_row?(attrs)
        batch << attrs.merge(created_at: Time.current, updated_at: Time.current)
        if batch.size >= 1000
          PostalCode.insert_all(batch, unique_by: nil)
          inserted += batch.size
          batch.clear
        end
      end
      if batch.any?
        PostalCode.insert_all(batch, unique_by: nil)
        inserted += batch.size
      end
      @logger.info "Sepomex::Importer inserted #{inserted} postal code rows"
      inserted
    end

    private
    def normalize_row(h)
      h.transform_values! { |v| v.to_s.strip }
      {
        cp: h['cp'],
        state: h['state'],
        municipality: h['municipality'],
        settlement: h['settlement'],
        settlement_type: h['settlement_type']
      }
    end

    def valid_row?(attrs)
      attrs[:cp].to_s.match?(/\A\d{5}\z/) && attrs[:state].present? && attrs[:municipality].present? && attrs[:settlement].present?
    end
  end
end
