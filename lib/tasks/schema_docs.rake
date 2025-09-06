namespace :introspection do
  desc "Genera o actualiza db/schema_docs.yml con todas las tablas y columnas (no destructivo)"
  task generate_schema_docs: :environment do
    require 'yaml'
    path = Rails.root.join('db', 'schema_docs.yml')
    existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    conn = ActiveRecord::Base.connection
    tables = conn.tables.sort
    updated = existing.deep_dup

    tables.each do |table|
      updated[table] ||= { '_comment' => "TODO: describir tabla #{table}" }
      cols = conn.columns(table)
      cols.each do |c|
        updated[table][c.name] ||= "TODO: describir columna #{table}.#{c.name} (#{c.sql_type})"
      end
    end

    File.write(path, updated.to_yaml)
    puts "Schema docs actualizado: #{path}"

    # Métricas progreso
    total_cols = 0
    documented_cols = 0
    tables.each do |t|
      cols = conn.columns(t).map(&:name)
      cols.each do |cn|
        total_cols += 1
        val = updated.dig(t, cn)
        documented_cols += 1 if val && !val.start_with?('TODO:')
      end
    end
    puts "Tablas: #{tables.size} | Columnas documentadas: #{documented_cols}/#{total_cols} (#{(documented_cols*100.0/total_cols).round(1)}%)"
  end

  desc "Aplica comentarios de db/schema_docs.yml a PostgreSQL (tablas y columnas)"
  task apply_comments: :environment do
    conn = ActiveRecord::Base.connection
    unless conn.adapter_name =~ /postgres/i
      puts "Adapter #{conn.adapter_name} no soporta comentarios nativos (sólo Postgres)."; next
    end
    path = Rails.root.join('db', 'schema_docs.yml')
    abort "No existe #{path}" unless File.exist?(path)
    docs = YAML.load_file(path) || {}

    applied_tables = 0
    applied_columns = 0
    docs.each do |table, meta|
      next unless conn.tables.include?(table)
      table_comment = meta['_comment']
      if table_comment && !table_comment.start_with?('TODO:')
        begin
          conn.change_table_comment(table, table_comment) if conn.respond_to?(:change_table_comment)
          applied_tables += 1
        rescue => e
          warn "No se pudo comentar tabla #{table}: #{e.message}"
        end
      end
      meta.each do |col, comment|
        next if col == '_comment'
        next if comment.nil? || comment.start_with?('TODO:')
        begin
          if conn.columns(table).map(&:name).include?(col)
            conn.change_column_comment(table, col, comment) if conn.respond_to?(:change_column_comment)
            applied_columns += 1
          end
        rescue => e
          warn "No se pudo comentar columna #{table}.#{col}: #{e.message}"
        end
      end
    end
    puts "Comentarios aplicados. Tablas: #{applied_tables}, Columnas: #{applied_columns}"
  end

  desc "Muestra progreso de documentación de schema_docs.yml"
  task dictionary_progress: :environment do
    conn = ActiveRecord::Base.connection
    path = Rails.root.join('db', 'schema_docs.yml')
    unless File.exist?(path)
      puts 'Aún no existe schema_docs.yml (ejecuta introspection:generate_schema_docs)'; next
    end
    docs = YAML.load_file(path) || {}
    tables = conn.tables.sort
    total_cols = 0
    documented_cols = 0
    tables.each do |t|
      conn.columns(t).each do |c|
        total_cols += 1
        v = docs.dig(t, c.name)
        documented_cols += 1 if v && !v.start_with?('TODO:')
      end
    end
    puts "Tablas totales: #{tables.size}"
    puts "Columnas documentadas: #{documented_cols}/#{total_cols} (#{(documented_cols*100.0/total_cols).round(1)}%)"
    pending_tables = tables.select { |t| (docs.dig(t, '_comment') || '').start_with?('TODO:') }
    puts "Tablas sin _comment: #{pending_tables.size}" unless pending_tables.empty?
  end
end
