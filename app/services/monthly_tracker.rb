class MonthlyTracker
	KEY_PREFIX = "mt".freeze

	def initialize(namespace: "default")
		@namespace = namespace
	end

	# Incrementa un contador para la llave dada (por ejemplo eventos, orders, etc.).
	def track(counter, by: 1)
		k = redis_key(counter)
		if redis_available?
			redis.incrby(k, by.to_i)
			redis.expire(k, seconds_until_month_end)
		else
			memory[k] = memory.fetch(k, 0) + by.to_i
		end
		true
	rescue => e
		Rails.logger.error("MonthlyTracker#track error #{e.class}: #{e.message}")
		false
	end

	# Obtiene el valor actual del contador
	def get(counter)
		k = redis_key(counter)
		if redis_available?
			(redis.get(k) || 0).to_i
		else
			memory.fetch(k, 0)
		end
	end

	# Devuelve un hash con todos los contadores activos bajo el namespace (solo Redis)
	def stats
		if redis_available?
			pattern = pattern_key("*")
			keys = redis.scan_each(match: pattern).to_a
			keys.sort.each_with_object({}) do |full_key, acc|
				name = full_key.split(":").last
				acc[name] = (redis.get(full_key) || 0).to_i
			end
		else
			memory.transform_keys { |k| k.split(":").last }
		end
	rescue => e
		Rails.logger.error("MonthlyTracker#stats error #{e.class}: #{e.message}")
		{}
	end

	def to_json(*_args)
		{ namespace: @namespace, month: current_month_key, stats: stats }.to_json
	end

	private

	def redis_key(counter)
		pattern_key(counter)
	end

	def pattern_key(suffix)
		[KEY_PREFIX, @namespace, current_month_key, suffix].join(":")
	end

	def current_month_key
		Time.current.utc.strftime("%Y%m")
	end

	def seconds_until_month_end
		now = Time.current.utc
		start_next = (now.to_date.next_month.beginning_of_month).to_time.utc
		(start_next - now).to_i
	end

	def redis
		@redis ||= if defined?(Redis) && ENV['REDIS_URL']
			Redis.new(url: ENV['REDIS_URL'])
		elsif defined?(::Redis) && Rails.respond_to?(:cache) && Rails.cache.respond_to?(:redis)
			Rails.cache.redis
		end
	end

	def redis_available?
		!!redis
	rescue
		false
	end

	def memory
		@memory ||= {}
	end
end

