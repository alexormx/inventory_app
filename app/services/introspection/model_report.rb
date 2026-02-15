# frozen_string_literal: true

module Introspection
  class ModelReport
    def initialize(limit: 100, include_zero: false)
      @limit = limit
      @include_zero = include_zero
    end

    def call
      models = ActiveRecord::Base.descendants.select { |m| m.name.present? && m.table_exists? }
      data = models.map do |m|
        c = safe_count(m)
        next if !@include_zero && c.zero?

        { model: m.name, table: m.table_name, count: c }
      rescue StandardError => e
        { model: m.name, table: m.table_name, error: e.message }
      end.compact
      sorted = data.sort_by { |h| - (h[:count] || 0) }
      {
        generated_at: Time.current.utc.iso8601,
        total_models: models.size,
        listed: sorted.first(@limit)
      }
    end

    def to_json(*_args)
      call.to_json
    end

    private

    def safe_count(model)
      model.limit(1).pluck(Arel.sql('1')) # fuerza carga mínima para detectar errores
      model.count
    end
  end
end
