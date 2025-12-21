# frozen_string_literal: true

class NewsletterSubscribersController < ApplicationController
  def create
    @subscriber = NewsletterSubscriber.find_or_initialize_by(email: subscriber_params[:email]&.downcase&.strip)

    if @subscriber.new_record?
      @subscriber.subscribed_at = Time.current
      if @subscriber.save
        respond_to do |format|
          format.html { redirect_back fallback_location: root_path, notice: '¡Gracias por suscribirte! Recibirás nuestras novedades.' }
          format.turbo_stream { flash.now[:notice] = '¡Gracias por suscribirte!' }
        end
      else
        respond_to do |format|
          format.html { redirect_back fallback_location: root_path, alert: @subscriber.errors.full_messages.first }
          format.turbo_stream { flash.now[:alert] = @subscriber.errors.full_messages.first }
        end
      end
    elsif @subscriber.unsubscribed_at.present?
      @subscriber.subscribe!
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: '¡Te has re-suscrito exitosamente!' }
        format.turbo_stream { flash.now[:notice] = '¡Te has re-suscrito!' }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: 'Ya estás suscrito a nuestro newsletter.' }
        format.turbo_stream { flash.now[:notice] = 'Ya estás suscrito.' }
      end
    end
  end

  private

  def subscriber_params
    params.require(:newsletter_subscriber).permit(:email)
  end
end
