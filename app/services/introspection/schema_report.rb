# frozen_string_literal: true

module Introspection
  class SchemaReport
    def initialize(limit: nil, include_indexes: false)
      @limit = limit
      @include_indexes = include_indexes
    end

    def call
      conn = ActiveRecord::Base.connection
      tables = conn.data_sources.sort
      tables = tables.first(@limit) if @limit
      data = tables.map { |t| table_info(conn, t) }
      {
        generated_at: Time.current.utc.iso8601,
        tables_count: tables.size,
        include_indexes: @include_indexes,
        tables: data
      }
    rescue StandardError => e
      { error: e.message }
    end

    def to_json(*_args)
      call.to_json
    end

    private

    def table_info(conn, table)
      cols = conn.columns(table).map do |c|
        {
          name: c.name,
          sql_type: c.sql_type,
          type: c.type,
          default: c.default,
          null: c.null
        }
      end
      info = { name: table, columns: cols }
      if @include_indexes
        info[:indexes] = conn.indexes(table).map do |i|
          { name: i.name, columns: i.columns, unique: i.unique }
        end
      end
      info
    end
  end
end
