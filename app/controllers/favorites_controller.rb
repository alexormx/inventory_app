# frozen_string_literal: true

# Lista de deseos del cliente. Sólo funciona con sesión: un visitante que toca
# el corazón llega aquí con ?add=<product_id>, Devise lo manda a iniciar
# sesión y lo regresa a esta misma URL, que guarda el producto.
class FavoritesController < ApplicationController
  before_action :authenticate_user!
  layout 'customer'

  HEART_VARIANTS = %w[full card inline].freeze

  def index
    return save_pending_and_return if params[:add].present?

    @favorites = current_user.favorites.open.includes(product: { product_images_attachments: :blob })
                             .order(created_at: :desc)
    product_ids = @favorites.map(&:product_id)
    @available_now = Hash.new(0)
    Inventories::Availability.counts_for(product_ids, for_cart: current_holding_cart)
                             .each { |(product_id, condition), count| @available_now[product_id] += count if condition == 'brand_new' }
  end

  def create
    product = Product.find(params[:product_id])
    Favorite.save_for(current_user, product)
    respond_with_heart(product, saved: true)
  end

  def destroy
    product = Product.find(params[:id])
    current_user.favorites.open.find_by(product: product)&.remove!
    respond_with_heart(product, saved: false)
  end

  private

  def save_pending_and_return
    product = Product.find_by(id: params[:add])
    return redirect_to(favorites_path) if product.nil?

    Favorite.save_for(current_user, product)
    redirect_to product_path(product), notice: 'Guardado en tus favoritos.'
  end

  def respond_with_heart(product, saved:)
    respond_to do |format|
      format.turbo_stream do
        streams = [turbo_stream.replace("favorite_heart_#{product.id}",
                                        partial: 'favorites/heart',
                                        locals: { product: product, saved: saved, variant: heart_variant })]
        streams << turbo_stream.remove("favorite_row_#{product.id}") unless saved
        streams << turbo_stream.replace('favorites-count', partial: 'favorites/nav_count')
        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: favorites_path }
    end
  end

  # El corazón de la página del producto es un botón con texto; el de las
  # tarjetas flota sobre la foto y el de la lista va en línea.
  def heart_variant
    HEART_VARIANTS.include?(params[:variant]) ? params[:variant].to_sym : :card
  end
end
