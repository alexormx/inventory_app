# frozen_string_literal: true

module Products
  module Enrichment
    # Publishes an approved draft to the Product record.
    # Copies draft_content → product.description
    # Copies draft_attributes → product.custom_attributes
    # Marks draft as published with timestamp and admin reference.
    class PublishDraftService
      class PublishError < StandardError; end

      def initialize(draft, published_by:)
        @draft = draft
        @published_by = published_by
      end

      def call
        validate!

        ActiveRecord::Base.transaction do
          product = @draft.product

          product.update!(
            description:       @draft.draft_content,
            custom_attributes: @draft.draft_attributes.presence || product.custom_attributes
          )

          @draft.update!(
            status:          :published,
            published_at:    Time.current,
            published_by:    @published_by
          )

          # Mark any older drafts for this product as rejected
          product.description_drafts
                 .where.not(id: @draft.id)
                 .where(status: [:queued, :draft_generated])
                 .update_all(status: :rejected) # rubocop:disable Rails/SkipsModelValidations
        end

        @draft
      end

      private

      def validate!
        raise PublishError, "Draft is not in publishable state (status: #{@draft.status})" unless @draft.publishable?
        raise PublishError, "Draft content is blank" if @draft.draft_content.blank?
        raise PublishError, "Published_by user is required" unless @published_by
      end
    end
  end
end
