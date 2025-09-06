module Introspection
  class SchemaReport
    COLUMN_ATTRS = %i[name type default null].freeze
    YAML_PATH = Rails.root.join('db', 'schema_docs.yml')

    def self.call(force: false)
      # Simplificamos: sin caché (o implementar luego basada en mtime de YAML)
      new.generate
    end

    def generate
      @yaml_docs = load_yaml_docs
      @pg_comments = fetch_pg_comments
      conn = ActiveRecord::Base.connection
      tables = conn.tables.sort.map { |t| build_table(conn, t) }
      { generated_at: Time.current, tables: tables }
    end

    private

    def build_table(conn, table_name)
      raw_columns = conn.columns(table_name)
      indexes = conn.indexes(table_name).map { |i| { name: i.name, columns: i.columns, unique: i.unique } }
      index_columns = indexes.flat_map { |i| i[:columns] }.uniq
      fks = if conn.respond_to?(:foreign_keys)
              conn.foreign_keys(table_name).map do |fk|
                { column: fk.column, to_table: fk.to_table, primary_key: fk.primary_key, on_delete: fk.on_delete }
              end
            else
              []
            end
      fk_map = fks.map { |fk| [fk[:column], fk] }.to_h

      cols = raw_columns.map do |c|
        base = COLUMN_ATTRS.index_with { |attr| c.public_send(attr) }
        base[:indexed] = index_columns.include?(c.name)
        if (fk = fk_map[c.name])
          base[:foreign_key] = fk[:to_table]
          base[:fk_on_delete] = fk[:on_delete]
        end
        base[:comment] = column_comment(table_name, c.name)
        base
      end

      {
        name: table_name,
        comment: table_comment(table_name),
        columns: cols,
        indexes: indexes,
        foreign_keys: fks
      }
    rescue => e
      { name: table_name, error: e.message }
    end

    # ---- Comments helpers ----
    def load_yaml_docs
      return {} unless File.exist?(YAML_PATH)
      YAML.load_file(YAML_PATH) || {}
    rescue StandardError
      {}
    end

    def fetch_pg_comments
      conn = ActiveRecord::Base.connection
      return { tables: {}, columns: {} } unless conn.adapter_name =~ /postgres/i
      table_sql = <<~SQL
        SELECT c.relname AS table_name, obj_description(c.oid) AS comment
        FROM pg_class c
        WHERE c.relkind = 'r'
      SQL
      col_sql = <<~SQL
        SELECT c.relname AS table_name, a.attname AS column_name, pgd.description AS comment
        FROM pg_catalog.pg_description pgd
        JOIN pg_catalog.pg_attribute a ON a.attrelid = pgd.objoid AND a.attnum = pgd.objsubid
        JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
        WHERE c.relkind = 'r'
      SQL
      tables = conn.select_all(table_sql).to_a.each_with_object({}) { |r,h| h[r['table_name']] = r['comment'] }
      columns = Hash.new { |h,k| h[k] = {} }
      conn.select_all(col_sql).to_a.each do |r|
        columns[r['table_name']][r['column_name']] = r['comment']
      end
      { tables: tables, columns: columns }
    rescue StandardError
      { tables: {}, columns: {} }
    end

    def table_comment(table)
      @yaml_docs.dig(table, '_comment') || @pg_comments[:tables][table]
    end

    def column_comment(table, column)
      @yaml_docs.dig(table, column) || @pg_comments[:columns].dig(table, column)
    end
  end
end

