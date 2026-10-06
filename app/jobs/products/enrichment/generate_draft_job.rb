# frozen_string_literal: true

module Products
  module Enrichment
    # Background job wrapper for GenerateDraftService.
    # Creates or reuses a draft, then generates via OpenAI.
    class GenerateDraftJob < ApplicationJob
      queue_as :enrichment

      # ActiveJob revisa los manejadores de abajo hacia arriba: las subclases
      # (abajo) ganan sobre GenerationError, que se descarta sin reintentar.
      discard_on Products::Enrichment::GenerateDraftService::GenerationError
      retry_on Products::Enrichment::GenerateDraftService::InvalidResponseError, wait: 5.seconds, attempts: 2
      retry_on Products::Enrichment::GenerateDraftService::TransientError, wait: :polynomially_longer, attempts: 3
      retry_on Products::Enrichment::GenerateDraftService::RateLimitError, wait: :polynomially_longer, attempts: 5

      discard_on ActiveRecord::RecordNotFound

      # Encola un borrador nuevo salvo que el producto ya tenga uno pendiente.
      def self.enqueue_for(product)
        return if product.description_drafts.exists?(status: %i[queued generating draft_generated])

        perform_later(product.description_drafts.create!(status: :queued).id)
      end

      def perform(draft_id)
        draft = ProductDescriptionDraft.find(draft_id)
        return if draft.draft_generated? || draft.published?

        Products::Enrichment::GenerateDraftService.new(draft).call
      end
    end
  end
end
