# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductsHelper, type: :helper do
  # These examples exercise each availability decision as one cohesive helper contract.
  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  describe 'condition-aware cart availability' do
    it 'passes each selected condition to stock and reservation calculations' do
      %w[brand_new misb mib mint].each do |condition|
        product = instance_double(
          Product,
          current_on_hand: 1,
          in_transit_count: 0,
          preorder_available: false,
          backorder_allowed: false
        )
        allow(product).to receive(:split_immediate_and_pending)
          .with(1, condition: condition)
          .and_return({ pending: 0, pending_type: nil })
        allow(helper).to receive(:earliest_in_transit_eta)
          .with(product, condition: condition)
          .and_return(nil)

        html = helper.stock_badge(product, quantity: 1, condition: condition)

        expect(html).to include('En stock')
        expect(product).to have_received(:current_on_hand).with(condition: condition)
      end
    end

    it 'does not describe an unavailable collectible as preorder or backorder' do
      product = instance_double(
        Product,
        current_on_hand: 0,
        in_transit_count: 0,
        preorder_available: true,
        backorder_allowed: true
      )
      allow(product).to receive(:split_immediate_and_pending)
        .with(1, condition: 'mint')
        .and_return({ pending: 1, pending_type: nil })
      allow(helper).to receive(:earliest_in_transit_eta)
        .with(product, condition: 'mint')
        .and_return(nil)

      html = helper.stock_badge(product, quantity: 1, condition: 'mint')

      expect(html).to include('Fuera de stock')
      expect(html).not_to include('Preventa', 'Sobre pedido')
      expect(helper.stock_eta(product, condition: 'mint')).to be_nil
    end

    it 'shows condition-specific transit even when its ETA is not known' do
      product = instance_double(
        Product,
        current_on_hand: 0,
        in_transit_count: 1,
        preorder_available: false,
        backorder_allowed: false
      )
      allow(product).to receive(:split_immediate_and_pending)
        .with(1, condition: 'mib')
        .and_return({ pending: 0, pending_type: nil })
      allow(helper).to receive(:earliest_in_transit_eta)
        .with(product, condition: 'mib')
        .and_return(nil)

      html = helper.stock_badge(product, quantity: 1, condition: 'mib')

      expect(html).to include('En tránsito')
      expect(product).to have_received(:in_transit_count).with(condition: 'mib')
    end

    it 'does not query transit when immediate stock already determines the badge' do
      product = instance_double(
        Product,
        current_on_hand: 1,
        preorder_available: false,
        backorder_allowed: false
      )
      allow(product).to receive(:in_transit_count)
      allow(helper).to receive(:earliest_in_transit_eta)

      html = helper.stock_badge(product)

      expect(html).to include('En stock')
      expect(product).not_to have_received(:in_transit_count)
      expect(helper).not_to have_received(:earliest_in_transit_eta)
    end

    it 'uses an explicit zero transit override without calling the product fallback' do
      product = instance_double(
        Product,
        current_on_hand: 0,
        preorder_available: false,
        backorder_allowed: false
      )
      allow(product).to receive(:in_transit_count)

      html = helper.stock_badge(product, in_transit_override: 0, in_transit_eta_override: nil)

      expect(html).to include('Fuera de stock')
      expect(product).not_to have_received(:in_transit_count)
    end

    it 'preserves product-level transit when no condition or override is provided' do
      product = instance_double(
        Product,
        current_on_hand: 0,
        in_transit_count: 2,
        preorder_available: false,
        backorder_allowed: false
      )
      allow(helper).to receive(:earliest_in_transit_eta).with(product, condition: nil).and_return(nil)

      html = helper.stock_badge(product)

      expect(html).to include('En tránsito')
      expect(product).to have_received(:in_transit_count).with(no_args)
    end

    it 'accepts a symbol condition and handles an invalid condition without leaking other stock' do
      product = instance_double(
        Product,
        current_on_hand: 1,
        in_transit_count: 0,
        preorder_available: true,
        backorder_allowed: true
      )
      allow(helper).to receive(:earliest_in_transit_eta).with(product, condition: :mint).and_return(nil)

      symbol_html = helper.stock_badge(product, condition: :mint)
      invalid_html = helper.stock_badge(product, condition: 'not-a-condition')

      expect(symbol_html).to include('En stock')
      expect(invalid_html).to include('Fuera de stock')
    end

    it 'preserves preorder and backorder labels for the orderable condition' do
      [
        [{ preorder_available: true, backorder_allowed: false }, 'Preventa'],
        [{ preorder_available: false, backorder_allowed: true }, 'Sobre pedido']
      ].each do |availability, expected_label|
        product = instance_double(Product, **availability, launch_date: nil)

        html = helper.stock_badge(
          product,
          condition: 'brand_new',
          on_hand_override: 0,
          in_transit_override: 0,
          in_transit_eta_override: nil
        )

        expect(html).to include(expected_label)
      end
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  describe '#catalog_event_for' do
    it 'returns nil when no event is within its window' do
      product = Product.new(first_published_at: 200.days.ago, republished_at: 200.days.ago, restocked_at: 200.days.ago)
      expect(helper.catalog_event_for(product)).to be_nil
    end

    it 'returns nil when the product has no event timestamps' do
      expect(helper.catalog_event_for(Product.new)).to be_nil
    end

    it 'flags a recently first-published product as :new' do
      product = Product.new(first_published_at: 2.days.ago)
      expect(helper.catalog_event_for(product)[:type]).to eq(:new)
    end

    it 'flags a recently republished product as :reappeared' do
      product = Product.new(republished_at: 2.days.ago)
      expect(helper.catalog_event_for(product)[:type]).to eq(:reappeared)
    end

    it 'flags a recently restocked product as :restocked' do
      product = Product.new(restocked_at: 2.days.ago)
      expect(helper.catalog_event_for(product)[:type]).to eq(:restocked)
    end

    it 'prefers :new over :restocked when both apply' do
      product = Product.new(first_published_at: 2.days.ago, restocked_at: 1.day.ago)
      expect(helper.catalog_event_for(product)[:type]).to eq(:new)
    end

    it 'prefers :reappeared over :restocked when both apply' do
      product = Product.new(republished_at: 2.days.ago, restocked_at: 1.day.ago)
      expect(helper.catalog_event_for(product)[:type]).to eq(:reappeared)
    end

    it 'honors the configurable window from SiteSetting' do
      SiteSetting.set('badge_new_days', 3, 'integer')
      recent = Product.new(first_published_at: 2.days.ago)
      stale  = Product.new(first_published_at: 5.days.ago)
      expect(helper.catalog_event_for(recent)&.dig(:type)).to eq(:new)
      expect(helper.catalog_event_for(stale)).to be_nil
    end
  end

  describe '#catalog_event_badge' do
    it 'renders nil when no event applies' do
      expect(helper.catalog_event_badge(Product.new)).to be_nil
    end

    it 'renders a badge span with the event label' do
      product = Product.new(first_published_at: 1.day.ago)
      html = helper.catalog_event_badge(product)
      expect(html).to include('Nuevo en catálogo')
      expect(html).to include('badge-new')
    end
  end
end
