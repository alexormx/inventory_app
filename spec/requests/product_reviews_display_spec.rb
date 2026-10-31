# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reseñas en la página de producto', type: :request do
  let(:product) { create(:product) }

  it 'muestra "Cliente" y nunca el correo cuando el autor no tiene nombre' do
    author = create(:user, name: nil, email: 'coleccionista.privado@example.com')
    Review.create!(product: product, user: author, rating: 5, body: 'Excelente pieza, muy bien empacada.', status: :approved)

    get product_path(product)

    expect(response.body).to include('Excelente pieza')
    expect(response.body).not_to include('coleccionista.privado')
    expect(Nokogiri::HTML(response.body).at_css('#reseñas footer').text).to include('Cliente')
  end

  it 'deja el formulario de reseña plegado detrás de "Escribir reseña"' do
    sign_in create(:user)

    get product_path(product)

    toggle = Nokogiri::HTML(response.body).at_css('#reseñas details.review-form-toggle')
    expect(toggle['open']).to be_nil
    expect(toggle.at_css('summary').text).to include('Escribir reseña')
    expect(toggle.at_css('form.review-form')).to be_present
  end
end
