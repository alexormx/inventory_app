# frozen_string_literal: true

class HomeController < ApplicationController
  layout 'customer'

  def index
    # Show 8 featured products (active, newest first)
    # Note: stock filtering happens in the view since current_on_hand is calculated
    @products = Product.active
                       .order(created_at: :desc)
                       .limit(12) # Fetch more to ensure we have 8+ with stock

    # Statistics for the homepage
    @stats = {
      products: Product.active.count,
      customers: User.where(role: 'customer').count,
      years: [(Time.current.year - 2020), 1].max # Years since founded
    }
  end
end
