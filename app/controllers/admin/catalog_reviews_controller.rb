# frozen_string_literal: true

require "open-uri"

module Admin
  class CatalogReviewsController < ApplicationController
    include SupplierCatalogItemsHelper

    before_action :authenticate_user!
    before_action :authorize_admin!

    # GET /admin/catalog_review
    def show
      parse_filters
      build_filtered_product_ids
      @total_count = @product_ids.size

      if @total_count.zero?
        @product = nil
        return
      end

      @current_index = @index.clamp(0, @total_count - 1)
      @product = Product.includes(:supplier_catalog_item, :product_catalog_review,
                                  product_images_attachments: :blob)
                        .find(@product_ids[@current_index])

      @catalog_item = @product.supplier_catalog_item
      @is_reviewed = @product.product_catalog_review.present?

      if @catalog_item.present?
        build_sync_data
        @name_similarity = name_similarity_score(@catalog_item.canonical_name, @product.product_name)
      else
        build_suggestions
      end
    end

    # POST /admin/catalog_review/link
    def link
      product = Product.find(params[:product_id])
      catalog_item = SupplierCatalogItem.find(params[:catalog_item_id])
      catalog_item.update!(product: product)
      redirect_to review_url_for(params[:index]), notice: "Producto vinculado a \"#{catalog_item.canonical_name}\"."
    rescue ActiveRecord::RecordNotFound
      redirect_to review_url_for(params[:index]), alert: "Registro no encontrado."
    end

    # POST /admin/catalog_review/unlink
    def unlink
      product = Product.find(params[:product_id])
      product.supplier_catalog_item&.update!(product_id: nil)
      redirect_to review_url_for(params[:index]), notice: "Producto desvinculado."
    rescue ActiveRecord::RecordNotFound
      redirect_to review_url_for(params[:index]), alert: "Producto no encontrado."
    end

    # POST /admin/catalog_review/sync_fields
    def sync_fields
      product = Product.find(params[:product_id])
      catalog_item = product.supplier_catalog_item

      if catalog_item.blank?
        redirect_to review_url_for(params[:index]), alert: "El producto no está vinculado."
        return
      end

      applied_count = apply_sync_to_product(product, catalog_item)
      redirect_to review_url_for(params[:index]), notice: "Sincronización aplicada (#{applied_count} cambios)."
    rescue StandardError => e
      redirect_to review_url_for(params[:index]), alert: "Error: #{e.message}"
    end

    # PATCH /admin/catalog_review/update_name
    def update_name
      product = Product.find(params[:product_id])
      product.update!(product_name: params[:product_name])
      redirect_to review_url_for(params[:index]), notice: "Nombre actualizado."
    rescue StandardError => e
      redirect_to review_url_for(params[:index]), alert: "Error: #{e.message}"
    end

    # POST /admin/catalog_review/mark_reviewed
    def mark_reviewed
      product = Product.find(params[:product_id])
      ProductCatalogReview.find_or_create_by!(product: product) do |r|
        r.reviewed_by = current_user
        r.reviewed_at = Time.current
        r.review_mode = Array(params[:modes]).join(",")
      end
      redirect_to review_url_for(params[:index]), notice: "Producto marcado como revisado."
    rescue StandardError => e
      redirect_to review_url_for(params[:index]), alert: "Error: #{e.message}"
    end

    # POST /admin/catalog_review/unmark_reviewed
    def unmark_reviewed
      ProductCatalogReview.find_by(product_id: params[:product_id])&.destroy
      redirect_to review_url_for(params[:index]), notice: "Marca de revisado eliminada."
    end

    private

    def parse_filters
      @modes = Array(params[:modes]).select(&:present?)
      @modes = %w[unlinked missing_data mismatch low_similarity] if @modes.empty?
      @show_reviewed = params[:show_reviewed] == "1"
      @q = params[:q].to_s.strip
      @index = params[:index].to_i
    end

    def build_filtered_product_ids
      # Build separate scopes for each mode, then combine with UNION (via Ruby array union)
      ids = Set.new

      if @modes.include?("unlinked")
        ids.merge(unlinked_product_ids)
      end

      if @modes.include?("missing_data")
        ids.merge(missing_data_product_ids)
      end

      if @modes.include?("mismatch")
        ids.merge(mismatch_product_ids)
      end

      if @modes.include?("low_similarity")
        ids.merge(low_similarity_product_ids)
      end

      # Exclude reviewed unless opted in
      unless @show_reviewed
        reviewed_ids = ProductCatalogReview.pluck(:product_id)
        ids.subtract(reviewed_ids)
      end

      # Apply text search filter
      if @q.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@q.downcase)}%"
        matching_ids = Product.where("LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?", term, term).pluck(:id)
        ids = ids & matching_ids.to_set
      end

      # Deterministic order by product_name
      @product_ids = Product.where(id: ids.to_a).order(:product_name).pluck(:id)
    end

    def unlinked_product_ids
      Product.left_joins(:supplier_catalog_item)
             .where(supplier_catalog_items: { id: nil })
             .pluck(:id)
    end

    def missing_data_product_ids
      Product.joins(:supplier_catalog_item)
             .where(<<~SQL).pluck("products.id")
               products.barcode IS NULL OR products.barcode = ''
               OR supplier_catalog_items.barcode IS NULL OR supplier_catalog_items.barcode = ''
               OR products.supplier_product_code IS NULL OR products.supplier_product_code = ''
               OR supplier_catalog_items.supplier_product_code IS NULL OR supplier_catalog_items.supplier_product_code = ''
             SQL
    end

    def mismatch_product_ids
      barcode_mismatch = Product.joins(:supplier_catalog_item)
        .where(<<~SQL).pluck("products.id")
          products.barcode IS NOT NULL AND products.barcode != ''
          AND supplier_catalog_items.barcode IS NOT NULL AND supplier_catalog_items.barcode != ''
          AND products.barcode != supplier_catalog_items.barcode
        SQL

      code_mismatch = Product.joins(:supplier_catalog_item)
        .where(<<~SQL).pluck("products.id")
          products.supplier_product_code IS NOT NULL AND products.supplier_product_code != ''
          AND supplier_catalog_items.supplier_product_code IS NOT NULL AND supplier_catalog_items.supplier_product_code != ''
          AND products.supplier_product_code != supplier_catalog_items.supplier_product_code
        SQL

      (barcode_mismatch + code_mismatch).uniq
    end

    def low_similarity_product_ids
      Product.joins(:supplier_catalog_item)
             .select("products.id, products.product_name, supplier_catalog_items.canonical_name")
             .map { |p| [p.id, name_similarity_score(p.canonical_name, p.product_name)] }
             .select { |_id, score| score < 0.6 }
             .map(&:first)
    end

    def build_sync_data
      catalog = @catalog_item
      product = @product
      parsed_dims = parse_catalog_dimensions(catalog.details_payload)

      @syncable_fields = []
      @syncable_fields << { key: "barcode", label: "Barcode", catalog_val: catalog.barcode, product_val: product.barcode, different: catalog.barcode.present? && catalog.barcode != product.barcode }
      @syncable_fields << { key: "supplier_product_code", label: "Código proveedor", catalog_val: catalog.supplier_product_code, product_val: product.supplier_product_code, different: catalog.supplier_product_code.present? && catalog.supplier_product_code != product.supplier_product_code }
      @syncable_fields << { key: "launch_date", label: "Fecha lanzamiento", catalog_val: catalog.canonical_release_date&.to_s, product_val: product.launch_date&.to_s, different: catalog.canonical_release_date.present? && catalog.canonical_release_date.to_s != product.launch_date.to_s }
      @syncable_fields << { key: "weight_gr", label: "Peso (g)", catalog_val: parsed_dims[:weight_gr]&.to_s, product_val: product.weight_gr&.to_s, different: parsed_dims[:weight_gr].present? && parsed_dims[:weight_gr] != product.weight_gr&.to_f }
      @syncable_fields << { key: "length_cm", label: "Largo (cm)", catalog_val: parsed_dims[:length_cm]&.to_s, product_val: product.length_cm&.to_s, different: parsed_dims[:length_cm].present? && parsed_dims[:length_cm] != product.length_cm&.to_f }
      @syncable_fields << { key: "width_cm", label: "Ancho (cm)", catalog_val: parsed_dims[:width_cm]&.to_s, product_val: product.width_cm&.to_s, different: parsed_dims[:width_cm].present? && parsed_dims[:width_cm] != product.width_cm&.to_f }
      @syncable_fields << { key: "height_cm", label: "Alto (cm)", catalog_val: parsed_dims[:height_cm]&.to_s, product_val: product.height_cm&.to_s, different: parsed_dims[:height_cm].present? && parsed_dims[:height_cm] != product.height_cm&.to_f }

      @catalog_images = Array(catalog.image_urls).select(&:present?)
      @product_images = product.product_images.to_a
    end

    def build_suggestions
      product = @product
      suggestions = []

      # By barcode (exact)
      if product.barcode.present?
        SupplierCatalogItem.unlinked.where(barcode: product.barcode).limit(3).each do |sci|
          score = name_similarity_score(sci.canonical_name, product.product_name)
          suggestions << { item: sci, score: score, match_reason: "barcode" }
        end
      end

      # By barcode (similar / partial match)
      if product.barcode.present? && product.barcode.length >= 4
        existing_ids = suggestions.map { |s| s[:item].id }
        barcode_like = "%#{ActiveRecord::Base.sanitize_sql_like(product.barcode)}%"
        SupplierCatalogItem.unlinked
          .where.not(id: existing_ids)
          .where("barcode LIKE ? OR ? LIKE '%' || barcode || '%'", barcode_like, product.barcode)
          .where("barcode IS NOT NULL AND barcode != ''")
          .limit(5).each do |sci|
            score = name_similarity_score(sci.canonical_name, product.product_name)
            suggestions << { item: sci, score: score, match_reason: "barcode similar" }
          end
      end

      # By supplier_product_code
      if product.supplier_product_code.present?
        existing_ids = suggestions.map { |s| s[:item].id }
        SupplierCatalogItem.unlinked
          .where(supplier_product_code: product.supplier_product_code)
          .where.not(id: existing_ids)
          .limit(3).each do |sci|
            score = name_similarity_score(sci.canonical_name, product.product_name)
            suggestions << { item: sci, score: score, match_reason: "supplier_code" }
          end
      end

      # By name keywords
      keywords = extract_name_keywords(product.product_name)
      if keywords.any?
        existing_ids = suggestions.map { |s| s[:item].id }
        conditions = keywords.map { "LOWER(canonical_name) LIKE ?" }
        values = keywords.map { |kw| "%#{ActiveRecord::Base.sanitize_sql_like(kw.downcase)}%" }
        SupplierCatalogItem.unlinked
          .where.not(id: existing_ids)
          .where(conditions.join(" OR "), *values)
          .limit(10).each do |sci|
            score = name_similarity_score(sci.canonical_name, product.product_name)
            suggestions << { item: sci, score: score, match_reason: "name" }
          end
      end

      @suggestions = suggestions.sort_by { |s| -s[:score] }.first(8)
    end

    def extract_name_keywords(name)
      name.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split.select { |w| w.length >= 3 }.uniq.first(6)
    end

    def apply_sync_to_product(product, catalog_item)
      selected = Array(params[:sync_fields])
      parsed_dims = parse_catalog_dimensions(catalog_item.details_payload)
      applied_count = 0

      ActiveRecord::Base.transaction do
        field_map = {
          "barcode" => -> { product.barcode = catalog_item.barcode if catalog_item.barcode.present? },
          "supplier_product_code" => -> { product.supplier_product_code = catalog_item.supplier_product_code if catalog_item.supplier_product_code.present? },
          "launch_date" => -> { product.launch_date = catalog_item.canonical_release_date if catalog_item.canonical_release_date.present? },
          "weight_gr" => -> { product.weight_gr = parsed_dims[:weight_gr] if parsed_dims[:weight_gr].present? },
          "length_cm" => -> { product.length_cm = parsed_dims[:length_cm] if parsed_dims[:length_cm].present? },
          "width_cm" => -> { product.width_cm = parsed_dims[:width_cm] if parsed_dims[:width_cm].present? },
          "height_cm" => -> { product.height_cm = parsed_dims[:height_cm] if parsed_dims[:height_cm].present? }
        }

        selected.each do |key|
          if field_map[key]
            field_map[key].call
            applied_count += 1
          end
        end

        # Image additions
        Array(params[:add_images]).select(&:present?).each do |url|
          downloaded = URI.open(url) # rubocop:disable Security/Open
          filename = File.basename(URI.parse(url).path)
          product.product_images.attach(io: downloaded, filename: filename, content_type: downloaded.content_type)
          applied_count += 1
        rescue StandardError => e
          Rails.logger.warn("[CatalogReview] Failed to download #{url}: #{e.message}")
        end

        # Image removals
        Array(params[:remove_images]).map(&:to_i).select(&:positive?).each do |blob_id|
          attachment = product.product_images.find { |a| a.blob_id == blob_id }
          if attachment
            attachment.purge_later
            applied_count += 1
          end
        end

        product.save!
      end

      applied_count
    end

    def review_url_for(index)
      admin_catalog_review_path(
        modes: Array(params[:modes]).select(&:present?),
        index: index,
        show_reviewed: params[:show_reviewed],
        q: params[:q].presence
      )
    end
  end
end
