# frozen_string_literal: true

module Collectibles
  # Las fotos de búsquedas con IA sólo sirven mientras se da de alta la pieza.
  # A los 7 días se purgan; el registro (resultado y costo) se queda.
  class AiLookupPhotoPurgeJob < ApplicationJob
    queue_as :default

    def perform
      with_photos = ActiveStorage::Attachment.where(record_type: Collectibles::AiLookup.name, name: 'photos').select(:record_id)
      Collectibles::AiLookup.where(created_at: ...7.days.ago, id: with_photos)
                            .find_each { |lookup| lookup.photos.purge }
    end
  end
end
