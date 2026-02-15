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
    first_image = product.product_images.first
    image_loc = if first_image.present?
                  blob = first_image.blob
                  Rails.application.routes.url_helpers.rails_service_blob_proxy_url(
                    blob.signed_id,
                    blob.filename,
                    host: SitemapGenerator::Sitemap.default_host
                  )
                end

    add product_path(product),
        lastmod: product.updated_at,
        changefreq: 'weekly',
        priority: 0.8,
        images: if image_loc.present?
                  [{
                    loc: image_loc,
                    title: product.product_name,
                    caption: "#{product.product_name} - #{product.brand}"
                  }]
                else
                  []
                end
  end
end
