# frozen_string_literal: true

# Set the host name for URL creation
SitemapGenerator::Sitemap.default_host = ENV.fetch('APP_HOST', 'http://example.com')

SitemapGenerator::Sitemap.create do
  add root_path, changefreq: 'daily'
  add products_path, changefreq: 'weekly'
end
