module Introspection
	class EnvUsageReport
		REDACT_KEYS = /(key|secret|password|token|access)/i.freeze

		def initialize(filter: nil)
			@filter = filter
		end

		def call
			entries = ENV.to_h.sort_by { |k, _| k }.map do |k, v|
				next if skip_key?(k)
				next if @filter && k !~ /#{@filter}/i
				{ key: k, value: redact(k, v), length: v.to_s.length }
			end.compact
			{
				generated_at: Time.current.utc.iso8601,
				total: entries.size,
				entries: entries
			}
		end

		def to_json(*_args)
			call.to_json
		end

		private

		def skip_key?(k)
			k.start_with?("BUNDLE_", "RUBY_", "GEM_")
		end

		def redact(k, v)
			return v unless k =~ REDACT_KEYS
			return "" if v.nil?
			"***REDACTED(#{[v.length, 3].max})***"
		end
	end
end

