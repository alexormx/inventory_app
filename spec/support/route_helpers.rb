# frozen_string_literal: true

module RouteHelpersFallback
  def catalog_path(**opts)
    "/catalog"
  end
end

RSpec.configure do |config|
  config.include RouteHelpersFallback, type: :request
end
