# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Carts::ExpireIdleCartsJob do
  def cart_with_line(idle_for:)
    item = create(:shopping_cart_item, shopping_cart: create(:shopping_cart, :owned))
    item.shopping_cart.update_columns(last_activity_at: idle_for.ago)
    item.shopping_cart
  end

  it 'vence sólo los carritos con líneas y más de 4 h sin cambios' do
    stale = cart_with_line(idle_for: 5.hours)
    fresh = cart_with_line(idle_for: 1.hour)
    empty = create(:shopping_cart, :owned).tap { |c| c.update_columns(last_activity_at: 5.hours.ago) }

    expect(described_class.perform_now).to eq(1)
    expect(stale.reload.status).to eq('expired')
    expect(fresh.reload.status).to eq('active')
    expect(empty.reload.status).to eq('active')
  end
end
