# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductsHelper, type: :helper do
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
