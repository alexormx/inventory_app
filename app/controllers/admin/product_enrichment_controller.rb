# frozen_string_literal: true

module Admin
  class ProductEnrichmentController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_draft, only: [:show, :regenerate, :update_draft, :publish, :reject]

    # GET /admin/product_enrichment
    # Dashboard: overview of enrichment status
    def index
      @counts = {
        without_description: Product.without_description.count,
        queued:              ProductDescriptionDraft.queued.count,
        generating:          ProductDescriptionDraft.generating.count,
        draft_generated:     ProductDescriptionDraft.reviewable.count,
        published:           ProductDescriptionDraft.published.count,
        failed:              ProductDescriptionDraft.failed.count
      }
      @recent_drafts = ProductDescriptionDraft.recent.includes(:product).limit(20)
    end

    # GET /admin/product_enrichment/queue
    # List of products without description, ready to enrich
    def queue
      @products = Product.without_description
                         .left_joins(:inventories)
                         .select(
                           "products.*",
                           "COUNT(CASE WHEN inventories.status = 0 THEN 1 END) AS available_count",
                           "COUNT(CASE WHEN inventories.status = 0 AND inventories.inventory_location_id IS NOT NULL THEN 1 END) AS located_count"
                         )
                         .group("products.id")

      if params[:brand].present?
        @products = @products.where(brand: params[:brand])
      end

      if params[:category].present?
        @products = @products.where(category: params[:category])
      end

      case params[:sort]
      when "name"
        @products = @products.order("products.product_name ASC")
      when "newest"
        @products = @products.order("products.created_at DESC")
      else # default: prioritized — located first, then by available inventory desc
        @products = @products.order(
          Arel.sql("located_count DESC, available_count DESC, products.product_name ASC")
        )
      end

      @products = @products.page(params[:page]).per(20)

      @brands = Product.without_description.distinct.pluck(:brand).compact.sort
      @categories = Product.without_description.distinct.pluck(:category).compact.sort
    end

    # GET /admin/product_enrichment/:id
    # Show draft review screen (draft belongs to a product)
    def show
      @product = @draft.product
      @template = @product.attribute_template
      @history = @product.description_drafts.order(created_at: :desc)
    end

    # POST /admin/product_enrichment/:id/generate
    # Create a new draft and enqueue generation for a given product
    def generate
      product = Product.friendly.find(params[:id])
      draft = product.description_drafts.create!(status: :queued)
      Products::Enrichment::GenerateDraftJob.perform_later(draft.id)

      redirect_to admin_product_enrichment_path(draft),
                  notice: "Borrador en cola de generación. Se procesará en un momento."
    end

    # POST /admin/product_enrichment/:id/regenerate
    # Create a new draft for a product that already has one
    def regenerate
      product = @draft.product
      @draft.update!(status: :rejected) if @draft.draft_generated?

      new_draft = product.description_drafts.create!(status: :queued)
      Products::Enrichment::GenerateDraftJob.perform_later(new_draft.id)

      redirect_to admin_product_enrichment_path(new_draft),
                  notice: "Regenerando borrador con IA..."
    end

    # PATCH /admin/product_enrichment/:id/update_draft
    # Admin edits the draft content/attributes before publishing
    def update_draft
      if @draft.update(draft_update_params)
        redirect_to admin_product_enrichment_path(@draft), notice: "Borrador actualizado."
      else
        @product = @draft.product
        @template = @product.attribute_template
        @history = @product.description_drafts.order(created_at: :desc)
        flash.now[:alert] = "Error al actualizar borrador."
        render :show, status: :unprocessable_entity
      end
    end

    # POST /admin/product_enrichment/:id/publish
    # Publish draft to product
    def publish
      service = Products::Enrichment::PublishDraftService.new(@draft, published_by: current_user)
      service.call

      redirect_to admin_product_path(@draft.product),
                  notice: "Descripción y atributos publicados correctamente."
    rescue Products::Enrichment::PublishDraftService::PublishError => e
      redirect_to admin_product_enrichment_path(@draft), alert: "Error: #{e.message}"
    end

    # POST /admin/product_enrichment/:id/reject
    def reject
      @draft.update!(status: :rejected, admin_notes: params[:admin_notes])
      redirect_to admin_product_enrichment_index_path, notice: "Borrador rechazado."
    end

    private

    def set_draft
      @draft = ProductDescriptionDraft.find_by(id: params[:id])
      return if @draft

      # If :id is a product slug/id, find its latest draft or redirect to generate
      redirect_to admin_product_enrichment_index_path, alert: "Borrador no encontrado."
    end

    def draft_update_params
      params.require(:product_description_draft).permit(:draft_content, :admin_notes, draft_attributes: {})
    end
  end
end
