# frozen_string_literal: true

module Admin
  # Endpoints JSON de la búsqueda con IA de quick_add: crear (sube la foto y
  # encola) y consultar estado. Cada admin sólo ve sus propias búsquedas.
  class CollectibleAiLookupsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    # GET /admin/collectibles/ai_lookups/:id
    def show
      lookup = Collectibles::AiLookup.where(user: current_user).find(params[:id])
      render json: lookup.as_status_json
    end

    # POST /admin/collectibles/ai_lookups
    def create
      if Collectibles::AiLookup.daily_limit_reached?
        return render json: { error: "Se alcanzó el límite de #{Collectibles::AiLookup::DAILY_LIMIT} búsquedas con IA por hoy." },
                      status: :too_many_requests
      end

      lookup = Collectibles::AiLookup.new(user: current_user, hints: params[:hints].to_s.strip.presence)
      uploaded_photos.each { |file| lookup.photos.attach(file) }

      if lookup.save
        Collectibles::AiLookupJob.perform_later(lookup.id)
        render json: { id: lookup.id, status_url: admin_collectible_ai_lookup_path(lookup) }, status: :created
      else
        render json: { error: lookup.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    private

    # `photo` (una sola) es lo que mandaba la versión anterior de la página; se
    # sigue aceptando por si alguien la tiene abierta durante el deploy.
    def uploaded_photos
      (Array(params[:photos]) + [params[:photo]]).select { |file| file.respond_to?(:read) }
    end
  end
end
