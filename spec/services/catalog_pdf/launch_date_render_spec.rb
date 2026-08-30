# frozen_string_literal: true

require 'rails_helper'

# Regresión visual del HTML del PDF: la fecha de lanzamiento no debe desplazar
# ni romper el resto de la tarjeta en ninguna de las combinaciones reales.
RSpec.describe 'CatalogPdf: render con fecha de lanzamiento' do
  def item(overrides = {})
    {
      code: 'AB01', name: 'Mazda 787B', brand: 'Tomica', series: 'Premium',
      scale: '1/64', price: 199.99, event: nil, event_label: nil,
      launch_date: '2026-03-04T10:30:00-06:00', unique_piece: false,
      image_url: nil
    }.merge(overrides)
  end

  def render(items:, include_launch_date:, orientation: :portrait, usd_rate: nil)
    ApplicationController.render(
      template: 'catalog_pdf/show',
      layout: false,
      locals: { title: 'Catálogo', whatsapp_number: '5215555555555', items: items,
                logo: nil, usd_rate: usd_rate, orientation: orientation,
                include_launch_date: include_launch_date }
    )
  end

  it 'omite la línea cuando la opción está apagada' do
    html = render(items: [item], include_launch_date: false)
    aggregate_failures do
      expect(html).not_to include('Lanzamiento:')
      expect(html).to include('Mazda 787B')
    end
  end

  it 'muestra la fecha formateada cuando la opción está encendida' do
    html = render(items: [item], include_launch_date: true)
    aggregate_failures do
      expect(html).to include('Lanzamiento:')
      expect(html).to include('04/03/2026')
    end
  end

  it 'omite limpiamente la línea si el producto no tiene fecha' do
    html = render(items: [item(launch_date: nil)], include_launch_date: true)
    aggregate_failures do
      expect(html).not_to include('Lanzamiento:')
      expect(html).to include('Mazda 787B')
    end
  end

  it 'convive con el precio en USD' do
    html = render(items: [item], include_launch_date: true, usd_rate: 17.5)
    aggregate_failures do
      expect(html).to include('Lanzamiento:')
      expect(html).to include('MXN')
      expect(html).to include('USD')
    end
  end

  it 'convive con los badges de evento y pieza única' do
    html = render(items: [item(event: 'reappeared', event_label: 'De vuelta', unique_piece: true)],
                  include_launch_date: true)
    aggregate_failures do
      expect(html).to include('De vuelta')
      expect(html).to include('Lanzamiento:')
      expect(html).to include('badge-reappeared')
    end
  end

  it 'no rompe con un nombre largo' do
    long = 'Mazda 787B Edición Especial Aniversario Renown Charge Le Mans 1991 Conmemorativa'
    html = render(items: [item(name: long)], include_launch_date: true)
    aggregate_failures do
      expect(html).to include('Lanzamiento:')
      expect(html).to include('Mazda 787B Edición')
    end
  end

  %i[portrait landscape].each do |orientation|
    it "renderiza en #{orientation} sin perder la escala ni el código" do
      html = render(items: [item], include_launch_date: true, orientation: orientation)
      aggregate_failures do
        expect(html).to include('Lanzamiento:')
        expect(html).to include('Escala 1/64')
        expect(html).to include('AB01')
      end
    end
  end

  it 'mantiene una sola línea de lanzamiento por tarjeta' do
    items = Array.new(6) { |i| item(code: "AB0#{i}") }
    html = render(items: items, include_launch_date: true)
    expect(html.scan('Lanzamiento:').size).to eq(6)
  end
end
