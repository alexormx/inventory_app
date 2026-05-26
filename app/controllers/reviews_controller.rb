# frozen_string_literal: true

class ReviewsController < ApplicationController
  layout 'customer'
  before_action :authenticate_user!
  before_action :set_product

  def create
    review = @product.reviews.build(review_params)
    review.user = current_user
    review.verified_purchase = Review.user_purchased?(current_user, @product)
    review.status = :pending

    if review.save
      redirect_to product_path(@product, anchor: 'reseñas'),
                  notice: 'Tu reseña fue enviada y está pendiente de moderación. ¡Gracias!'
    else
      redirect_to product_path(@product, anchor: 'reseñas'),
                  alert: "No se pudo guardar tu reseña: #{review.errors.full_messages.to_sentence}"
    end
  end

  private

  def set_product
    @product = Product.friendly.find(params[:product_id])
    return if @product.active?

    redirect_to catalog_path, alert: 'Este producto no está disponible.'
  end

  def review_params
    params.require(:review).permit(:rating, :title, :body)
  end
end
