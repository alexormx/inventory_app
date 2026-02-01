# frozen_string_literal: true

class SitemapRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[SitemapRefreshJob] Starting sitemap refresh at #{Time.current}"

    # Generate sitemap
    SitemapGenerator::Interpreter.run

    # Ping search engines
    SitemapGenerator::Sitemap.ping_search_engines if Rails.env.production?

    Rails.logger.info "[SitemapRefreshJob] Sitemap refresh completed at #{Time.current}"
  rescue StandardError => e
    Rails.logger.error "[SitemapRefreshJob] Failed: #{e.message}"
    raise # Re-raise to let Solid Queue handle retry
  end
end
