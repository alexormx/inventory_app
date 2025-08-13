require 'rails_helper'

RSpec.describe 'Product gallery', type: :system, js: true do
  let(:product) { create(:product) }  # Revisa la factory (necesitamos verla)

  before do
    driven_by :selenium_chrome_headless
    product.product_images.purge if product.product_images.attached?
    %w[test1.png test2.png].each do |fname|
      product.product_images.attach(
        io: File.open(Rails.root.join('spec/fixtures/files', fname)),
        filename: fname,
        content_type: 'image/png'
      )
    end
  end

  it 'changes main image when clicking a thumbnail' do
    visit product_path(product)

    puts "DEBUG current_url: #{page.current_url}"
    puts "DEBUG page title: #{page.title}"

    # Asegura que realmente estamos en la ruta esperada (sin redirección)
    expect(page).to have_current_path(product_path(product), ignore_query: true)

    # Verifica que haya imágenes adjuntas del lado servidor
    puts "DEBUG attachments count: #{product.product_images.count}"

    expect(page).to have_css('#main-image', wait: 5)
    initial_src = find('#main-image')['src']

    expect(page).to have_css('img.thumbnail-image', minimum: 2)

    find_all('img.thumbnail-image')[1].click
    expect(page).to have_no_css("#main-image[src='#{initial_src}']", wait: 5)
  end
end