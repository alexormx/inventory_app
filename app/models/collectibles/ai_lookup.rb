# frozen_string_literal: true

module Collectibles
  # Una identificación con IA pedida desde quick_add: las fotos que se mandaron
  # (hasta 5, cada una con su tipo), las pistas del admin, en qué va y lo que contestó. Se guarda
  # aunque falle para poder ver costo y motivo; las fotos se purgan a los 7 días
  # (AiLookupPhotoPurgeJob).
  class AiLookup < ApplicationRecord
    self.table_name = 'collectible_ai_lookups'

    DAILY_LIMIT = 50
    STALE_AFTER = 3.minutes
    MAX_PHOTOS = 5
    MAX_PHOTO_BYTES = 15.megabytes
    PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    HINTS_MAX = 300
    # Un recuadro por tipo de foto en quick_add, en este orden. El texto es lo
    # que lee la IA antes de cada foto.
    PHOTO_ROLES = {
      'three_quarter' => 'vista 3/4 elevada de la pieza',
      'base' => 'base de la pieza, donde está el texto del casting (marca, modelo, año, país)',
      'side' => 'vista lateral',
      'top' => 'vista superior',
      'package' => 'empaque (caja, blíster o etiqueta)'
    }.freeze
    # Google Cloud Vision regala 1,000 consultas al mes; el tope es ese.
    VISION_MONTHLY_CAP = 1000

    belongs_to :user
    has_many_attached :photos

    enum :status, { pending: 0, running: 1, done: 2, failed: 3 }

    validate :photos_are_supported_images, on: :create
    validate :hints_fit
    validate :photo_roles_are_valid, on: :create

    def self.daily_limit_reached?
      where(created_at: Time.current.all_day).count >= DAILY_LIMIT
    end

    def self.vision_monthly_cap_reached?
      where(created_at: Time.current.all_month, vision_used: true).count >= VISION_MONTHLY_CAP
    end

    # En el orden en que el admin las eligió: la primera es la que va a Google.
    def ordered_photos
      photos_attachments.sort_by(&:id)
    end

    # Cada foto con su tipo (nil en búsquedas hechas antes de los recuadros).
    def labeled_photos
      ordered_photos.each_with_index.map { |photo, index| [photo, photo_roles[index]] }
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

    # Los errores van a :base para que el mensaje sea una oración completa en
    # español, sin el nombre del atributo en inglés delante.
    def photos_are_supported_images
      unless photos.attached?
        errors.add(:base, 'La foto es obligatoria.')
        return
      end

      errors.add(:base, "Máximo #{MAX_PHOTOS} fotos por búsqueda.") if photos.size > MAX_PHOTOS
      photos.each do |photo|
        unless PHOTO_CONTENT_TYPES.include?(photo.blob.content_type)
          errors.add(:base, "La foto #{photo.filename} tiene un formato no soportado: usa JPG, PNG, WEBP o GIF.")
        end
        errors.add(:base, "La foto #{photo.filename} pesa más de 15 MB.") if photo.blob.byte_size > MAX_PHOTO_BYTES
      end
    end

    def hints_fit
      errors.add(:base, "Las pistas no pueden pasar de #{HINTS_MAX} caracteres.") if hints.to_s.length > HINTS_MAX
    end

    # Sin tipos es una página vieja (antes de los recuadros) y se acepta.
    def photo_roles_are_valid
      roles = Array(photo_roles)
      return if roles.empty?

      if roles.size != photos.size || roles.uniq.size != roles.size || (roles - PHOTO_ROLES.keys).any?
        errors.add(:base, 'Los tipos de foto no son válidos.')
      elsif roles.exclude?('three_quarter')
        errors.add(:base, 'Falta la vista 3/4 elevada.')
      end
    end
  end
end
