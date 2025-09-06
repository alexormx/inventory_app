module Introspection
  class ModelReport
    COLUMN_ATTRS = %i[name type default null].freeze
    YAML_PATH = Rails.root.join('db', 'schema_docs.yml')

    def self.call
      new.generate
    end

    def generate
      eager_load_models
      load_docs
      models = ApplicationRecord.descendants.reject { |m| m.name.start_with?('ActiveStorage::') }
      models.sort_by!(&:name)
      { generated_at: Time.current, models: models.map { |m| build_model(m) } }
    end

    private

    def eager_load_models
      Rails.application.eager_load! unless ApplicationRecord.descendants.any?
    end

    def load_docs
      @yaml_docs = File.exist?(YAML_PATH) ? (YAML.load_file(YAML_PATH) || {}) : {}
      @pg_comments = fetch_pg_comments
    rescue StandardError
      @yaml_docs = {}
      @pg_comments = { tables: {}, columns: {} }
    end

    def fetch_pg_comments
      conn = ActiveRecord::Base.connection
      return { tables: {}, columns: {} } unless conn.adapter_name =~ /postgres/i
      tables = conn.select_all("SELECT c.relname AS table_name, obj_description(c.oid) AS comment FROM pg_class c WHERE c.relkind = 'r'").to_a
      table_comments = tables.each_with_object({}) { |r,h| h[r['table_name']] = r['comment'] }
      col_rows = conn.select_all(<<~SQL).to_a
        SELECT c.relname AS table_name, a.attname AS column_name, pgd.description AS comment
        FROM pg_catalog.pg_description pgd
        JOIN pg_catalog.pg_attribute a ON a.attrelid = pgd.objoid AND a.attnum = pgd.objsubid
        JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
        WHERE c.relkind = 'r'
      SQL
      col_comments = Hash.new { |h,k| h[k] = {} }
      col_rows.each { |r| col_comments[r['table_name']][r['column_name']] = r['comment'] }
      { tables: table_comments, columns: col_comments }
    rescue StandardError
      { tables: {}, columns: {} }
    end

    def table_comment(table)
      @yaml_docs.dig(table, '_comment') || @pg_comments[:tables][table]
    end

    def column_comment(table, column)
      @yaml_docs.dig(table, column) || @pg_comments[:columns].dig(table, column)
    end

    def build_model(model)
      conn = ActiveRecord::Base.connection
      cols = if model.table_exists?
               conn.columns(model.table_name).map do |c|
                 h = COLUMN_ATTRS.index_with { |attr| c.public_send(attr) }
                 h[:comment] = column_comment(model.table_name, c.name)
                 h
               end
             else
               []
             end
      associations = model.reflect_on_all_associations.group_by(&:macro).transform_values do |refs|
        refs.map { |r| { name: r.name, class_name: r.class_name, options: r.options.slice(:through, :polymorphic, :dependent) } }
      end
      enums = model.defined_enums
      validations = model.validators.map do |v|
        { attributes: v.attributes, kind: v.kind, options: v.options.slice(:allow_nil, :allow_blank, :in, :maximum, :minimum, :presence, :uniqueness, :format) }
      end
      raw = {
        name: model.name,
        table: model.table_name,
        abstract: model.abstract_class?,
        table_comment: table_comment(model.table_name),
        columns: cols,
        associations: associations,
        enums: enums,
        validations: validations
      }
      sanitize(raw)
    rescue => e
      { name: model.name, error: e.message }
    end

    def sanitize(value)
      case value
      when Hash then value.transform_values { |v| sanitize(v) }
      when Array then value.map { |v| sanitize(v) }
      when Regexp then value.source
      when Proc, Method then value.to_s
      else value end
    end
  end
end

