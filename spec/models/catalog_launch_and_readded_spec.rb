# frozen_string_literal: true

require 'rails_helper'

# Lanzamiento y regreso al catálogo son hechos comerciales distintos, y el
# catálogo público tiene que poder filtrarlos y ordenarlos por separado.
RSpec.describe 'Catálogo: lanzamiento y regreso' do
  describe CatalogQuery do
    it 'acepta launch_desc como orden válido' do
      expect(described_class.new('sort' => 'launch_desc').sort).to eq('launch_desc')
    end

    it 'no rompe el orden por defecto' do
      expect(described_class.new({}).sort).to eq(CatalogQuery::DEFAULT_SORT)
    end

    it 'reconoce el filtro de regreso reciente' do
      query = described_class.new('recently_readded' => '1')
      aggregate_failures do
        expect(query.recently_readded?).to be(true)
        expect(query.filters[:recently_readded]).to be(true)
        expect(query.filter_state.recently_readded_only).to be(true)
      end
    end

    it 'lo omite cuando no se pidió' do
      query = described_class.new({})
      aggregate_failures do
        expect(query.recently_readded?).to be(false)
        expect(query.query_parameters).not_to have_key('recently_readded')
      end
    end

    it 'conserva el filtro al reconstruir el query string' do
      query = described_class.new('recently_readded' => '1', 'q' => 'tomica', 'sort' => 'launch_desc')
      params = query.query_parameters
      aggregate_failures do
        expect(params['recently_readded']).to eq('1')
        expect(params['q']).to eq('tomica')
        expect(params['sort']).to eq('launch_desc')
      end
    end
  end

  describe 'Product.recently_readded' do
    def product_with(republished_at:)
      create(:product, skip_seed_inventory: true, status: 'active').tap do |p|
        p.update_columns(republished_at: republished_at)
      end
    end

    it 'incluye sólo los republicados dentro de la ventana' do
      SiteSetting.set('badge_republished_days', 15, 'integer')
      inside = product_with(republished_at: 2.days.ago)
      outside = product_with(republished_at: 40.days.ago)
      never = create(:product, skip_seed_inventory: true, status: 'active')

      ids = Product.recently_readded.pluck(:id)
      aggregate_failures do
        expect(ids).to include(inside.id)
        expect(ids).not_to include(outside.id)
        expect(ids).not_to include(never.id)
      end
    end

    # El badge visible puede ser otro (un resurtido más reciente) y aun así el
    # producto regresó al catálogo dentro de la ventana: el filtro se apoya en
    # la marca, no en el evento mostrado.
    it 'incluye un producto cuyo badge vigente es otro evento' do
      SiteSetting.set('badge_republished_days', 15, 'integer')
      product = product_with(republished_at: 3.days.ago)
      product.update_columns(restocked_at: 1.day.ago, first_published_at: 200.days.ago)

      aggregate_failures do
        expect(product.reload.catalog_event).to eq(:reappeared)
        expect(Product.recently_readded.pluck(:id)).to include(product.id)
      end
    end

    it 'no devuelve nada si la ventana está apagada' do
      SiteSetting.set('badge_republished_days', 0, 'integer')
      product_with(republished_at: 1.day.ago)
      expect(Product.recently_readded).to be_empty
    end
  end
end
