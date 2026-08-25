# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Recently viewed product resolver', type: :request do
  include ActiveJob::TestHelper

  def document
    Nokogiri::HTML.fragment(response.body)
  end

  def capture_queries(&block)
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s.squish
      next if payload[:cached]
      next if %w[SCHEMA CACHE].include?(payload[:name])
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  it 'is public, read-only, untracked, ordered, deduplicated and capped at ten products' do
    products = create_list(:product, 11)
    inactive = create(:product, status: 'inactive')
    requested = [
      products[3].slug,
      'not a valid slug',
      products[1].slug,
      products[3].slug,
      inactive.slug,
      'deleted-product',
      *products.drop(4).map(&:slug),
      products[0].slug,
      products[2].slug
    ]

    clear_enqueued_jobs
    expect do
      get '/products/recently_viewed', params: { slugs: requested }
    end.not_to have_enqueued_job(VisitorLogs::TrackJob)

    expect(response).to have_http_status(:ok)
    cards = document.css('.recently-viewed-card')
    expect(cards.size).to eq(10)
    expect(cards.map { |card| card['data-product-slug'] }).to eq(
      [products[3].slug, products[1].slug, *products.drop(4).map(&:slug), products[0].slug].first(10)
    )
    expect(response.body).not_to include(inactive.product_name, 'deleted-product')
  end

  it 'renders current name, price, path and primary image instead of historical presentation data' do
    product = create(:product, product_name: 'Current Product Name', selling_price: 650)
    product.set_primary_product_image!(product.product_images_attachments.last.id)

    get '/products/recently_viewed', params: { slugs: [product.slug] }

    card = document.at_css('.recently-viewed-card')
    image = card.at_css('img')
    expect(card['href']).to eq(product_path(product))
    expect(card.at_css('.recently-viewed-name').text).to eq('Current Product Name')
    expect(card.at_css('.recently-viewed-price').text).to eq('$650.00')
    expect(image['src']).to include(product.primary_product_image.filename.to_s)
    expect(image['src']).to include('/rails/active_storage/representations/proxy/')
  end

  it 'uses the current replacement image and current price, with no dependency on the old blob URL' do
    product = create(:product, product_name: 'Before Rename', selling_price: 600)
    product.product_images.purge
    product.product_images.attach(
      io: Rails.root.join('spec/fixtures/files/test1.png').open,
      filename: 'old-recently-viewed.png',
      content_type: 'image/png'
    )
    old_blob = product.primary_product_image.blob

    product.product_images.purge
    product.product_images.attach(
      io: Rails.root.join('spec/fixtures/files/test2.png').open,
      filename: 'current-recently-viewed.png',
      content_type: 'image/png'
    )
    product.update!(product_name: 'After Rename', selling_price: 650)

    get '/products/recently_viewed', params: { slugs: [product.slug] }

    expect(response.body).to include('After Rename', '$650.00', 'current-recently-viewed.png')
    expect(response.body).not_to include('Before Rename', '$600.00', old_blob.filename.to_s)
  end

  it 'renders a neutral placeholder for a current product without an image' do
    product = create(:product)
    product.product_images.purge

    get '/products/recently_viewed', params: { slugs: [product.slug] }

    image = document.at_css('.recently-viewed-thumb img')
    expect(response).to have_http_status(:ok)
    expect(image['src']).to include('placeholder')
    expect(image['alt']).to include('Imagen no disponible')
  end

  it 'preloads product image attachments and blobs without per-card queries' do
    products = create_list(:product, 10)

    queries = capture_queries do
      get '/products/recently_viewed', params: { slugs: products.map(&:slug) }
    end

    expect(response).to have_http_status(:ok)
    expect(queries.count { |sql| sql.include?('FROM "products"') }).to eq(1)
    expect(queries.count { |sql| sql.include?('FROM "active_storage_attachments"') }).to eq(1)
    expect(queries.count { |sql| sql.include?('FROM "active_storage_blobs"') }).to eq(1)
  end
end
