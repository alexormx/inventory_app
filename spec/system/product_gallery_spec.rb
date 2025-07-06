require 'rails_helper'

RSpec.describe 'Product gallery', type: :system, js: true do
  let!(:product) { create(:product) }

  before do
    product.product_images.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/test1.png')),
      filename: 'test1.png',
      content_type: 'image/png'
    )
    product.product_images.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/test2.png')),
      filename: 'test2.png',
      content_type: 'image/png'
    )
  end

  it 'changes main image when clicking next' do
    visit product_path(product)
    first_src = find('#main-image')[:src]
    find('#next-btn').click
    expect(find('#main-image')[:src]).not_to eq(first_src)
  end
end