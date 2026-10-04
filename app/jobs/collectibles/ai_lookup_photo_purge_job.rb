# frozen_string_literal: true

module Collectibles
  # Las fotos de búsquedas con IA sólo sirven mientras se da de alta la pieza.
  # A los 7 días se purgan; el registro (resultado y costo) se queda.
  class AiLookupPhotoPurgeJob < ApplicationJob
    queue_as :default

    def perform
      Collectibles::AiLookup.where(created_at: ...7.days.ago)
                            .joins(:photo_attachment)
                            .find_each { |lookup| lookup.photo.purge }
    end
  end
end
