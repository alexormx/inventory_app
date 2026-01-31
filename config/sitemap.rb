# frozen_string_literal: true

# Set the host name for URL creation
SitemapGenerator::Sitemap.default_host = ENV.fetch('APP_HOST', 'https://pasatiempos.com.mx')

# Compress sitemap for faster loading
SitemapGenerator::Sitemap.compress = true

SitemapGenerator::Sitemap.create do
  # Página principal - alta prioridad
  add root_path, changefreq: 'daily', priority: 1.0

  # Catálogo principal
  add catalog_path, changefreq: 'daily', priority: 0.9

  # Páginas estáticas importantes
  add about_path, changefreq: 'monthly', priority: 0.5 if defined?(about_path)
  add contact_path, changefreq: 'monthly', priority: 0.5 if defined?(contact_path)

  # Todos los productos activos (status = 'active')
  Product.where(status: 'active').find_each do |product|
    add product_path(product),
        lastmod: product.updated_at,
        changefreq: 'weekly',
        priority: 0.8,
        images: product.product_images.attached? ? [{
          loc: Rails.application.routes.url_helpers.rails_blob_url(product.product_images.first, host: SitemapGenerator::Sitemap.default_host),
          title: product.product_name,
          caption: "#{product.product_name} - #{product.brand}"
        }] : []
  end

  # Categorías únicas como páginas de filtro
  Product.where(status: 'active').distinct.pluck(:category).compact.each do |category|
    add catalog_path(categories: [category]),
        changefreq: 'weekly',
        priority: 0.7
  end

  # Marcas únicas como páginas de filtro
  Product.where(status: 'active').distinct.pluck(:brand).compact.each do |brand|
    add catalog_path(brands: [brand]),
        changefreq: 'weekly',
        priority: 0.7
  end
end
