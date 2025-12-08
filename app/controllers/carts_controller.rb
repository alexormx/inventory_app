# frozen_string_literal: true

class CartsController < ApplicationController
  layout 'customer'

  def show
    @cart = Cart.new(session)
  end
end
