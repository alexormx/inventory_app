# frozen_string_literal: true

module FavoritesHelper
  # Una sola consulta por request para pintar todos los corazones de la página.
  def favorite_product_ids
    return Set.new unless user_signed_in?

    @favorite_product_ids ||= current_user.favorites.open.pluck(:product_id).to_set
  end

  def favorited?(product)
    favorite_product_ids.include?(product.id)
  end
end
