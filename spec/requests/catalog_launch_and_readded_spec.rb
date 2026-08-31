# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Catálogo público: lanzamiento y regreso', type: :request do
  def active_product(name:, first_published_at: nil, republished_at: nil)
    create(:product, skip_seed_inventory: true, status: 'active', product_name: name).tap do |p|
      p.update_columns(first_published_at: first_published_at, republished_at: republished_at)
    end
  end

  before { SiteSetting.set('badge_republished_days', 15, 'integer') }

  describe 'filtro "De vuelta recientemente"' do
    it 'devuelve sólo los productos republicados dentro de la ventana' do
      readded = active_product(name: 'Regresado', first_published_at: 200.days.ago, republished_at: 2.days.ago)
      old_readd = active_product(name: 'Viejo regreso', first_published_at: 300.days.ago, republished_at: 60.days.ago)
      never = active_product(name: 'Sin regreso', first_published_at: 10.days.ago)

      get catalog_path(recently_readded: '1')

      aggregate_failures do
        expect(response.body).to include('Regresado')
        expect(response.body).not_to include('Viejo regreso')
        expect(response.body).not_to include('Sin regreso')
        expect(readded.reload.catalog_event).to eq(:reappeared)
        expect(old_readd.reload.catalog_event).not_to eq(:reappeared)
        expect(never.reload.republished_at).to be_nil
      end
    end

    # El término va contra el NOMBRE: la factory pone 'Tomica' como marca en
    # todos, así que buscar por marca no distinguiría nada.
    it 'se combina con la búsqueda de texto' do
      active_product(name: 'Zafiro Regresado', first_published_at: 200.days.ago, republished_at: 2.days.ago)
      active_product(name: 'Esmeralda Regresado', first_published_at: 200.days.ago, republished_at: 2.days.ago)

      get catalog_path(recently_readded: '1', q: 'Zafiro')

      aggregate_failures do
        expect(response.body).to include('Zafiro Regresado')
        expect(response.body).not_to include('Esmeralda Regresado')
      end
    end

    it 'sin el filtro devuelve también los que no regresaron' do
      active_product(name: 'Sin regreso', first_published_at: 10.days.ago)
      get catalog_path
      expect(response.body).to include('Sin regreso')
    end
  end

  describe 'orden launch_desc' do
    it 'ordena por fecha de lanzamiento, no por alta del registro' do
      # El más viejo como registro es el lanzado más recientemente.
      older_record = active_product(name: 'Lanzado ayer', first_published_at: 1.day.ago)
      newer_record = active_product(name: 'Lanzado hace un año', first_published_at: 365.days.ago)

      get catalog_path(sort: 'launch_desc')

      body = response.body
      aggregate_failures do
        expect(body.index('Lanzado ayer')).to be < body.index('Lanzado hace un año')
        expect(older_record.first_published_at).to be > newer_record.first_published_at
      end
    end

    it 'deja al final los que nunca se publicaron' do
      active_product(name: 'Con lanzamiento', first_published_at: 5.days.ago)
      active_product(name: 'Nunca publicado')

      get catalog_path(sort: 'launch_desc')

      body = response.body
      expect(body.index('Con lanzamiento')).to be < body.index('Nunca publicado')
    end

    it 'responde correctamente combinado con el filtro de regreso' do
      active_product(name: 'Regreso reciente', first_published_at: 100.days.ago, republished_at: 1.day.ago)

      get catalog_path(sort: 'launch_desc', recently_readded: '1')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Regreso reciente')
      end
    end
  end
end
