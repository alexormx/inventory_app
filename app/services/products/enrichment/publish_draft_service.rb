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

          structured = @draft.structured_output || {}

          # Promote first-class attributes out of the JSON blob.
          # 'escala' was historically a custom_attribute; now it's a column.
          custom_attrs = (@draft.draft_attributes.presence || product.custom_attributes || {}).dup
          extracted_scale = custom_attrs.delete('escala').presence

          # Último filtro: un borrador editado a mano tampoco publica SKU ni códigos.
          scrubber = Products::Enrichment::ScrubIdentifiersService.new(product)
          description = scrubber.clean_text(@draft.draft_content)
          raise PublishError, "Draft content is blank after removing internal identifiers" if description.blank?

          product_updates = {
            description:       description,
            custom_attributes: custom_attrs,
            highlights:        scrubber.clean_list(structured["highlights"]).presence || product.highlights,
            seo_keywords:      scrubber.clean_list(structured["seo_keywords"]).presence || product.seo_keywords
          }
          product_updates[:scale] = extracted_scale if extracted_scale.present?

          product.update!(product_updates)

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
