# frozen_string_literal: true

class HomeController < ApplicationController
  layout 'customer'

  def index
    # Show 8 featured products (active, newest first)
    # Note: stock filtering happens in the view since current_on_hand is calculated
    @products = Product.active
                       .order(created_at: :desc)
                       .limit(12) # Fetch more to ensure we have 8+ with stock

    # Categorías reales con productos activos (las 6 más nutridas). Se
    # derivan de la BD para que las tarjetas nunca enlacen a categorías
    # vacías o inexistentes.
    @featured_categories = Product.active
                                  .where.not(category: [nil, ''])
                                  .group(:category)
                                  .order(Arel.sql('COUNT(*) DESC'))
                                  .limit(6)
                                  .count
                                  .keys

    # Statistics for the homepage
    @stats = {
      products: Product.active.count,
      customers: User.where(role: 'customer').count,
      years: [(Time.current.year - 2020), 1].max # Years since founded
    }
  end
end
