# frozen_string_literal: true

require 'csv'

module Finance
  # CSV de un MonthlyStatement::Result: mismas filas y columnas que la vista,
  # números sin formato con punto decimal, UTF-8 con BOM para Excel.
  #
  #   Finance::StatementCsv.new(result).call # => String
  class StatementCsv
    BOM = "\uFEFF"

    def initialize(result)
      @result = result
    end

    def call
      body = CSV.generate do |csv|
        csv << ['Concepto', *@result.periods.map(&:label), @result.history ? 'Total' : 'Total año']
        MonthlyStatement::ROW_LABELS.each do |key, label|
          csv << [label, *@result.rows.fetch(key).map { |v| cell(v) }, cell(@result.totals[key])]
        end
      end
      BOM + body
    end

    private

    def cell(value)
      case value
      when nil then ''
      when BigDecimal then value.to_s('F')
      else value.to_s
      end
    end
  end
end
