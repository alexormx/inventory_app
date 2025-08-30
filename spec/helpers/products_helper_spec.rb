require 'rails_helper'

RSpec.describe ProductsHelper, type: :helper do
  describe '#responsive_asset_image' do
    it 'devuelve html seguro con picture y img' do
      html = helper.responsive_asset_image('logo.png', alt: 'Logo')
      expect(html).to include('<picture')
      expect(html).to include('<img')
      expect(html).to include('alt="Logo"')
    end

    it 'retorna string vacío si filename blank' do
      expect(helper.responsive_asset_image('', alt: 'Nada')).to eq('')
    end
  end

  describe '#responsive_attachment_image' do
    let(:product) { create(:product) }

    it 'renderiza picture para attachment' do
      attachment = product.product_images.first
      html = helper.responsive_attachment_image(attachment, alt: 'Foto')
      expect(html).to include('<picture')
      expect(html).to include('alt="Foto"')
    end

    it 'usa placeholder si no hay attachment' do
      html = helper.responsive_attachment_image(nil, alt: 'X')
      expect(html).to include('placeholder')
    end
  end
end
