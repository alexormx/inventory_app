module Introspection
  class EnvUsageReport
    SENSITIVE = /(SECRET|PASSWORD|TOKEN|KEY|DATABASE_URL|RAILS_MASTER_KEY)/i
    CODE_GLOBS = [
      Rails.root.join('app', '**', '*.{rb,erb}'),
      Rails.root.join('config', '**', '*.{rb,yml}'),
      Rails.root.join('lib', '**', '*.rb')
    ].freeze
    REGEX = /ENV(?:\.fetch)?\(["']([A-Z0-9_]+)["']/

    def self.call
      Rails.cache.fetch('introspection:env_usage_report:v1', expires_in: 5.minutes) { new.generate }
    end

    def generate
      refs = Hash.new { |h,k| h[k] = { key: k, referenced_in: [] } }
      CODE_GLOBS.each do |glob|
        Dir.glob(glob).each do |file|
          next if File.directory?(file)
          content = File.read(file)
          content.scan(REGEX).flatten.uniq.each do |key|
            refs[key][:referenced_in] << relative(file)
          end
        rescue StandardError
          next
        end
      end
  refs.values.each { |h| enrich(h) }
      list = refs.values.sort_by { |h| h[:key] }
      missing = list.select { |h| !h[:present] }.map { |h| h[:key] }
      { generated_at: Time.current, total: list.size, keys: list, missing: missing }
    end

    private

    def relative(path)
      Pathname.new(path).relative_path_from(Rails.root).to_s
    end

    def enrich(entry)
      key = entry[:key]
      if ENV.key?(key)
        raw = ENV[key]
        entry[:present] = true
        entry[:value_preview] = raw && raw.length > 60 ? raw[0,57] + '…' : raw
        entry[:value_preview] = '***' if key =~ SENSITIVE
      else
        entry[:present] = false
        entry[:value_preview] = nil
      end
    end
  end
end
