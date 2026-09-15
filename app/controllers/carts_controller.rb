# frozen_string_literal: true

class CartsController < ApplicationController
  layout 'customer'

  def show
    @cart = current_cart
  end
end
