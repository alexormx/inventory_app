# frozen_string_literal: true

module Admin
  class SupplierCatalogReviewsController < ApplicationController
    REVIEW_WINDOW_DAYS = 10
    FEED_OPTIONS = {
      "recent_additions" => "Agregados HLJ (10 días)",
      "recent_arrivals" => "Arrivals HLJ (10 días)"
    }.freeze

    before_action :authenticate_user!
    before_action :authorize_admin!

    def show
      parse_filters
      @status_options = SupplierCatalogItem.distinct.order(:canonical_status).pluck(:canonical_status).compact
      build_filtered_item_ids
      @total_count = @item_ids.size

      if @total_count.zero?
        @supplier_catalog_item = nil
        return
      end

      @current_index = @index.clamp(0, @total_count - 1)
      @supplier_catalog_item = SupplierCatalogItem.includes(:product, :supplier_catalog_sources, :supplier_catalog_reviews)
                                                .find(@item_ids[@current_index])
      @review_record = @supplier_catalog_item.supplier_catalog_reviews.find_by(review_mode: @feed)
      @is_reviewed = @review_record.present?
      @review_timestamp = @supplier_catalog_item.review_timestamp_for(@feed)
      @recent_item_runs = SupplierSyncRun.where(source: "hlj", supplier_catalog_item: @supplier_catalog_item).recent.limit(5)
    end

    def mark_reviewed
      item = SupplierCatalogItem.find(params[:supplier_catalog_item_id])
      feed = normalized_feed(params[:feed])

      review = item.supplier_catalog_reviews.find_or_initialize_by(review_mode: feed)
      review.reviewed_by = current_user
      review.reviewed_at = Time.current
      review.notes = params[:notes].presence
      review.save!

      redirect_to review_url_for(params[:index]), notice: "Artículo marcado como revisado."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_supplier_catalog_review_path(feed: normalized_feed(params[:feed])), alert: "Artículo no encontrado."
    rescue StandardError => e
      redirect_to review_url_for(params[:index]), alert: "Error: #{e.message}"
    end

    def unmark_reviewed
      item = SupplierCatalogItem.find(params[:supplier_catalog_item_id])
      item.supplier_catalog_reviews.find_by(review_mode: normalized_feed(params[:feed]))&.destroy

      redirect_to review_url_for(params[:index]), notice: "Marca de revisado eliminada."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_supplier_catalog_review_path(feed: normalized_feed(params[:feed])), alert: "Artículo no encontrado."
    end

    private

    def parse_filters
      @feed = normalized_feed(params[:feed])
      @linked = params[:linked].to_s
      @status = params[:status].to_s
      @show_reviewed = params[:show_reviewed] == "1"
      @q = params[:q].to_s.strip
      @index = params[:index].to_i
      @feed_options = FEED_OPTIONS.map { |value, label| [label, value] }
    end

    def build_filtered_item_ids
      scope = base_scope_for_feed
      scope = scope.linked if @linked == "yes"
      scope = scope.unlinked if @linked == "no"
      scope = scope.where(canonical_status: @status) if @status.present?

      if @q.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@q.downcase)}%"
        scope = scope.where(
          "LOWER(canonical_name) LIKE ? OR LOWER(external_sku) LIKE ? OR LOWER(COALESCE(barcode, '')) LIKE ?",
          pattern, pattern, pattern
        )
      end

      unless @show_reviewed
        reviewed_ids = SupplierCatalogReview.where(review_mode: @feed).pluck(:supplier_catalog_item_id)
        scope = scope.where.not(id: reviewed_ids) if reviewed_ids.any?
      end

      @item_ids = scope.order(feed_timestamp_column => :desc, canonical_name: :asc).pluck(:id)
    end

    def base_scope_for_feed
      case @feed
      when "recent_arrivals"
        SupplierCatalogItem.recent_hlj_arrivals(REVIEW_WINDOW_DAYS)
      else
        SupplierCatalogItem.recent_hlj_additions(REVIEW_WINDOW_DAYS)
      end
    end

    def feed_timestamp_column
      @feed == "recent_arrivals" ? :last_hlj_recent_arrival_at : :last_hlj_recent_added_at
    end

    def normalized_feed(value)
      FEED_OPTIONS.key?(value.to_s) ? value.to_s : "recent_additions"
    end

    def review_url_for(index)
      admin_supplier_catalog_review_path(
        feed: @feed,
        linked: @linked.presence,
        status: @status.presence,
        q: @q.presence,
        show_reviewed: @show_reviewed ? "1" : nil,
        index: index
      )
    end
  end
end