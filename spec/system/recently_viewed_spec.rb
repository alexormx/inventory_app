# frozen_string_literal: true

require 'rails_helper'

Selenium::WebDriver.logger.level = :warn

# End-to-end browser stories intentionally assert each observable part of the
# recovery contract in one session.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'Recently viewed product recovery', :js, type: :system do
  let(:v1_key) { 'pasatiempos:recentlyViewed:v1' }
  let(:v2_key) { 'pasatiempos:recentlyViewed:v2' }

  before do
    driven_by :selenium_chrome_headless
  end

  def seed_storage(key, entries)
    page.execute_script(
      'window.localStorage.setItem(arguments[0], arguments[1])',
      key,
      JSON.generate(entries)
    )
  end

  def stored_json(key)
    raw = page.evaluate_script('window.localStorage.getItem(arguments[0])', key)
    raw && JSON.parse(raw)
  end

  it 'tracks only a stable slug and timestamp, then resolves the current card on catalog return' do
    product = create(:product, product_name: 'Visited Product', selling_price: 275)
    product.product_images.purge
    product.product_images.attach(
      io: Rails.root.join('spec/fixtures/files/test2.png').open,
      filename: 'visited-product-current.png',
      content_type: 'image/png'
    )

    visit product_path(product)
    accept_cookies_if_present

    history = stored_json(v2_key)
    expect(history.size).to eq(1)
    expect(history.first.keys).to contain_exactly('slug', 'at')
    expect(history.first['slug']).to eq(product.slug)
    expect(history.first['at']).to be_a(Integer)
    expect(page.evaluate_script('window.localStorage.getItem(arguments[0])', v1_key)).to be_nil

    visit catalog_path

    card = find('.recently-viewed-card', text: 'Visited Product')
    expect(card).to have_text('$275.00')
    expect(card).to have_css('img[src*="visited-product-current.png"]')
  end

  it 'self-heals stale v1 image, name, price and path data from current product state' do
    current = create(:product, product_name: 'Historical Name', selling_price: 600)
    current.product_images.purge
    current.product_images.attach(
      io: Rails.root.join('spec/fixtures/files/test1.png').open,
      filename: 'old-recently-viewed.png',
      content_type: 'image/png'
    )
    old_attachment = current.primary_product_image
    old_url = Rails.application.routes.url_helpers.rails_storage_proxy_path(old_attachment)

    current.product_images.purge
    current.product_images.attach(
      io: Rails.root.join('spec/fixtures/files/test2.png').open,
      filename: 'current-recently-viewed.png',
      content_type: 'image/png'
    )
    current.update!(product_name: 'Current Product Name', selling_price: 650)

    without_image = create(:product, product_name: 'Current Product Without Image')
    without_image.product_images.purge
    deleted = create(:product, product_name: 'Deleted Recently Viewed Product', skip_seed_inventory: true)
    deleted_slug = deleted.slug
    deleted.destroy!

    visit catalog_path
    accept_cookies_if_present
    seed_storage(v1_key, [
                   {
                     slug: current.slug,
                     name: 'Historical Name',
                     image: old_url,
                     price: '$600.00',
                     path: '/products/historical-path',
                     at: 300
                   },
                   {
                     slug: without_image.slug,
                     name: 'Historical Missing Image Name',
                     image: '/stale-missing-image.png',
                     price: '$1.00',
                     path: '/products/historical-missing-image',
                     at: 200
                   },
                   {
                     slug: deleted_slug,
                     name: 'Deleted Recently Viewed Product',
                     image: '/deleted-product-image.png',
                     price: '$2.00',
                     path: '/products/deleted-product',
                     at: 100
                   }
                 ])
    page.execute_script('performance.clearResourceTimings()')
    page.refresh

    expect(page).to have_css('.recently-viewed:not([hidden]) .recently-viewed-card', count: 2)
    cards = all('.recently-viewed-card')
    expect(cards.map { |card| card['data-product-slug'] }).to eq([current.slug, without_image.slug])
    expect(cards.first).to have_text('Current Product Name')
    expect(cards.first).to have_text('$650.00')
    expect(cards.first['href']).to end_with(product_path(current))
    expect(cards.first).to have_css('img[src*="current-recently-viewed.png"]')
    expect(cards[1]).to have_css('img[src*="placeholder"]')
    expect(page).to have_no_text('Historical Name')
    expect(page).to have_no_text('$600.00')
    expect(page).to have_no_text('Deleted Recently Viewed Product')

    requested_old_urls = page.evaluate_script(<<~JS)
      performance.getEntriesByType("resource").filter((entry) => {
        return [#{old_url.to_json}, "/stale-missing-image.png", "/deleted-product-image.png"]
          .some((path) => new URL(entry.name).pathname === path)
      }).map((entry) => entry.name)
    JS
    expect(requested_old_urls).to be_empty
    expect(stored_json(v2_key)).to eq([
                                        { 'slug' => current.slug, 'at' => 300 },
                                        { 'slug' => without_image.slug, 'at' => 200 },
                                        { 'slug' => deleted_slug, 'at' => 100 }
                                      ])
    expect(page.evaluate_script('window.localStorage.getItem(arguments[0])', v1_key)).to be_nil

    current_image = cards.first.find('img')
    expect(page.evaluate_script('arguments[0].complete && arguments[0].naturalWidth > 0', current_image)).to be(true)

    # Tras CUALQUIER navegación, la tira se reconstruye sola: Turbo restaura la
    # instantánea con las tarjetas cacheadas, y acto seguido el controlador se
    # reconecta y llama a `renderCurrentProducts`, que vacía el contenedor con
    # `replaceChildren()` y lo vuelve a llenar con la respuesta del servidor.
    # Eso es justo lo que hace que la tira se auto-repare, y es correcto.
    #
    # Por eso aquí NO se puede capturar un nodo y afirmar sobre él: entre
    # `have_css(count: 2)` —que ya se satisface con las tarjetas restauradas— y
    # la comprobación del texto, el controlador puede sustituir ese nodo, y la
    # aserción muere con StaleElementReferenceError aunque el DOM final sea
    # correcto. Medido: 4 fallos en 25 ejecuciones con `taskset -c 0,1`, y en el
    # fallo capturado el orden era correcto antes y después.
    #
    # `have_css` con el selector re-consulta el DOM vivo, así que expresa lo
    # mismo —la PRIMERA tarjeta muestra el producto actual— sin sostener una
    # referencia a través del re-render. Sigue fallando si el orden es otro.
    cards.first.click
    expect(page).to have_current_path(product_path(current))
    page.go_back
    expect(page).to have_css('.recently-viewed-card', count: 2)
    expect_first_recently_viewed_card('Current Product Name')

    find('#header-sort-form select[name="sort"]').select('Precio ↑')
    expect(page).to have_current_path(/sort=price_asc/, url: true)
    expect(page).to have_css('.recently-viewed-card', count: 2)
    expect_first_recently_viewed_card('Current Product Name')

    page.go_back
    expect(page).to have_css('.recently-viewed-card', count: 2)
    expect_first_recently_viewed_card('Current Product Name')

    page.go_forward
    expect(page).to have_current_path(/sort=price_asc/, url: true)
    expect(page).to have_css('.recently-viewed-card', count: 2)
    expect_first_recently_viewed_card('Current Product Name')
  end

  it 'falls back without a broken icon when a current image request fails' do
    product = create(:product)

    visit catalog_path
    seed_storage(v2_key, [{ slug: product.slug, at: 100 }])
    page.refresh

    image = find('.recently-viewed-card img')
    page.execute_script('arguments[0].dispatchEvent(new Event("error"))', image)

    expect(image['src']).to include('placeholder')
    expect(image['data-recently-viewed-fallback-applied']).to eq('true')
  end

  it 'hides deleted-only history and keeps the mobile strip scrollable without page overflow' do
    deleted = create(:product, skip_seed_inventory: true)
    deleted_slug = deleted.slug
    deleted.destroy!

    visit catalog_path
    seed_storage(v2_key, [{ slug: deleted_slug, at: 100 }])
    page.refresh
    expect(page).to have_css('.recently-viewed[hidden]', visible: :all)

    products = create_list(:product, 5)
    seed_storage(v2_key, products.each_with_index.map { |product, index| { slug: product.slug, at: 500 - index } })
    page.current_window.resize_to(390, 844)
    page.refresh

    expect(page).to have_css('.recently-viewed-card', count: 5)
    dimensions = page.evaluate_script(<<~JS)
      (() => {
        const strip = document.querySelector(".recently-viewed-track")
        return {
          stripScrollable: strip.scrollWidth > strip.clientWidth,
          bodyFitsViewport: document.documentElement.scrollWidth <= window.innerWidth
        }
      })()
    JS
    expect(dimensions).to eq('stripScrollable' => true, 'bodyFitsViewport' => true)
  end

  # Afirma sobre el DOM VIVO en vez de sostener un nodo: ver la nota en el
  # ejemplo de auto-reparación. `have_css` re-consulta, así que sobrevive al
  # re-render del controlador sin perder fuerza (sigue exigiendo que sea la
  # PRIMERA tarjeta).
  def expect_first_recently_viewed_card(name)
    expect(page).to have_css('.recently-viewed-track .recently-viewed-card:first-child', text: name)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
