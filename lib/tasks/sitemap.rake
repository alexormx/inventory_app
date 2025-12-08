# frozen_string_literal: true

namespace :sitemap do
  desc 'Generate sitemap'
  task generate: :environment do
    require 'sitemap_generator'
    load File.expand_path('../../config/sitemap.rb', __dir__)
    SitemapGenerator::Sitemap.create
  end
end