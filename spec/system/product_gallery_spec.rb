# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Product gallery', type: :system, js: true do
  let(:product) { create(:product) }

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

  def accept_cookies_if_present
    return unless page.has_button?('Aceptar', wait: 2)

    click_button 'Aceptar'
    expect(page).to have_no_css('#cookie-overlay', visible: true)
  end

  it 'switches slides with thumbnails and handles each arrow key once' do
    visit product_path(product)
    accept_cookies_if_present

    expect(page).to have_current_path(product_path(product), ignore_query: true)
    expect(page).to have_css('.gallery-slide[data-index]', count: 2, visible: :all)
    expect(page).to have_css('.thumb-btn[data-index]', count: 2)

    expect(page).to have_css('.gallery-slide[data-index="0"][aria-hidden="false"]', visible: true)
    expect(page).to have_css('.gallery-slide[data-index="1"][aria-hidden="true"]', visible: :all)
    expect(page).to have_css('.thumb-btn[data-index="0"][aria-current="true"]')

    find('.thumb-btn[data-index="1"]').click

    expect(page).to have_css('.gallery-slide[data-index="0"][aria-hidden="true"]', visible: :all)
    expect(page).to have_css('.gallery-slide[data-index="1"][aria-hidden="false"]', visible: true)
    expect(page).to have_css('.thumb-btn[data-index="1"][aria-current="true"]')

    find('.thumb-btn[data-index="0"]').click
    find('.thumb-btn[data-index="0"]').send_keys(:arrow_right)

    expect(page).to have_css('.gallery-slide[data-index="0"][aria-hidden="true"]', visible: :all)
    expect(page).to have_css('.gallery-slide[data-index="1"][aria-hidden="false"]', visible: true)
    expect(page).to have_css('.thumb-btn[data-index="1"][aria-current="true"]')

    find('.thumb-btn[data-index="1"]').send_keys(:arrow_left)

    expect(page).to have_css('.gallery-slide[data-index="0"][aria-hidden="false"]', visible: true)
    expect(page).to have_css('.gallery-slide[data-index="1"][aria-hidden="true"]', visible: :all)
    expect(page).to have_css('.thumb-btn[data-index="0"][aria-current="true"]')
  end
end
