# frozen_string_literal: true

module Products
  module Enrichment
    # Background job wrapper for GenerateDraftService.
    # Creates or reuses a draft, then generates via OpenAI.
    class GenerateDraftJob < ApplicationJob
      queue_as :enrichment

      retry_on Products::Enrichment::GenerateDraftService::GenerationError,
               wait: :polynomially_longer,
               attempts: 3

      discard_on ActiveRecord::RecordNotFound

      def perform(draft_id)
        draft = ProductDescriptionDraft.find(draft_id)
        return if draft.draft_generated? || draft.published?

        Products::Enrichment::GenerateDraftService.new(draft).call
      end
    end
  end
end
