# frozen_string_literal: true

module Collectibles
  # Una identificación con IA pedida desde quick_add: la foto que se mandó, en
  # qué va y lo que contestó. Se guarda aunque falle para poder ver costo y
  # motivo; la foto se purga a los 7 días (AiLookupPhotoPurgeJob).
  class AiLookup < ApplicationRecord
    self.table_name = 'collectible_ai_lookups'

    DAILY_LIMIT = 50
    STALE_AFTER = 3.minutes
    MAX_PHOTO_BYTES = 15.megabytes
    PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

    belongs_to :user
    has_one_attached :photo

    enum :status, { pending: 0, running: 1, done: 2, failed: 3 }

    validate :photo_is_supported_image, on: :create

    def self.daily_limit_reached?
      where(created_at: Time.current.all_day).count >= DAILY_LIMIT
    end

    # Si el worker se cae o OpenAI se cuelga, la página no debe girar para siempre.
    def stale?(now: Time.current)
      (pending? || running?) && created_at < now - STALE_AFTER
    end

    def as_status_json
      if stale?
        { id: id, status: 'failed', result: nil, error: 'La búsqueda tardó demasiado. Intenta de nuevo.' }
      else
        { id: id, status: status, result: done? ? result : nil, error: failed? ? error_message : nil }
      end
    end

    private

    def photo_is_supported_image
      unless photo.attached?
        errors.add(:photo, 'es obligatoria')
        return
      end

      errors.add(:photo, 'tiene un formato no soportado: usa JPG, PNG, WEBP o GIF') unless PHOTO_CONTENT_TYPES.include?(photo.blob.content_type)
      errors.add(:photo, 'pesa más de 15 MB') if photo.blob.byte_size > MAX_PHOTO_BYTES
    end
  end
end
