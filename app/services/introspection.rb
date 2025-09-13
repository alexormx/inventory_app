module Introspection
	module_function

	# Información básica de la app para endpoints internos de diagnóstico
	def info
		{
			ruby: RUBY_VERSION,
			rails: Rails.version,
			env: Rails.env,
			time: Time.current.utc.iso8601,
			pid: Process.pid,
			loaded_models: loaded_models_count,
			db_connections: db_connection_stats
		}
	end

	def loaded_models_count
		ActiveRecord::Base.descendants.select { |k| k.name.present? }.size
	rescue
		0
	end

	def db_connection_stats
		if ActiveRecord::Base.respond_to?(:connection_pool)
			pool = ActiveRecord::Base.connection_pool
			{ size: pool.size, busy: pool.connections.count { |c| c.in_use? }, dead: pool.dead_connections.length }
		else
			{}
		end
	rescue
		{}
	end

	# Representación JSON rápida
	def to_json(*_args)
		info.to_json
	end
end

