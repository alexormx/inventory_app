# frozen_string_literal: true

require "open-uri"

module Admin
  class SupplierCatalogItemsController < ApplicationController
    HLJ_DISCOVERY_PRESETS = {
      "all" => {
        label: "Todo HLJ",
        word: nil, makers: [], genre_codes: [], scales: [], series: nil
      },
      "tomica" => {
        label: "Buscar: tomica",
        word: "tomica",
        makers: [], genre_codes: [], scales: [], series: nil
      },
      "tomica_recent_additions" => {
        label: "Tomica agregados 10 días",
        word: "tomica",
        makers: [], genre_codes: [], scales: [], series: nil,
        date_added_within_days: 10,
        date_arrivals_within_days: nil,
        review_feed: "recent_additions"
      },
      "tomica_recent_arrivals" => {
        label: "Tomica arrivals 10 días",
        word: "tomica",
        makers: [], genre_codes: [], scales: [], series: nil,
        date_added_within_days: nil,
        date_arrivals_within_days: 10,
        review_feed: "recent_arrivals"
      },
      "takara_cars" => {
        label: "Takara Tomy — Cars & Bikes",
        word: nil,
        makers: ["Takara Tomy", "Tomy", "Tomytec", "Takara Tomy A.R.T.S"],
        genre_codes: ["Cars & Bikes"], scales: [], series: nil
      },
      "tomica_164" => {
        label: "Tomica 1/64 — Cars & Bikes",
        word: "tomica",
        makers: ["Takara Tomy"],
        genre_codes: ["Cars & Bikes"], scales: ["1/64"], series: nil
      },
      "tomica_premium" => {
        label: "Tomica Premium",
        word: "tomica premium",
        makers: ["Takara Tomy"],
        genre_codes: ["Cars & Bikes"], scales: [], series: nil
      }
    }.freeze

    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_supplier_catalog_item, only: [:show, :create_product, :link_product, :unlink_product, :clear_product_sku, :review_sync, :apply_sync, :sync_product, :refresh_hlj, :refresh_takara_tomy_mall, :refresh_tomica_fandom]

    def index
      prepare_catalog_view
    end

    def discovery
      prepare_discovery_view
    end

    def discovery_progress
      @active_discovery_run = active_discovery_run
      render partial: "discovery_progress_frame", locals: { run: @active_discovery_run }
    end

    def preview_discovery
      options = discovery_options_from_params
      @discovery_preview = Suppliers::Hlj::PreviewDiscoveryService.new(
        max_pages: options[:max_pages],
        word: options[:word],
        makers: options[:makers],
        genre_codes: options[:genre_codes],
        scales: options[:scales],
        series: options[:series],
        date_added_within_days: options[:date_added_within_days],
        date_arrivals_within_days: options[:date_arrivals_within_days]
      ).call

      prepare_discovery_view
      render :discovery
    rescue StandardError => e
      prepare_discovery_view
      flash.now[:alert] = "Error al consultar vista previa HLJ: #{e.message}"
      render :discovery, status: :unprocessable_content
    end

    def run_discovery
      options = discovery_options_from_params
      Suppliers::Hlj::WeeklyDiscoveryJob.perform_later(options)

      redirect_to discovery_admin_supplier_catalog_items_path,
                  notice: discovery_notice(options)
    end

    def stop_discovery
      run = active_discovery_run

      if run.blank?
        redirect_to discovery_admin_supplier_catalog_items_path, alert: "No hay una corrida HLJ activa para detener."
        return
      end

      run.request_stop!
      redirect_to discovery_admin_supplier_catalog_items_path, notice: "Se solicitó detener la corrida HLJ activa."
    end

    def cancel_discovery
      run = SupplierSyncRun.active.where(source: "hlj").order(created_at: :desc).first

      if run.blank?
        redirect_to discovery_admin_supplier_catalog_items_path, alert: "No hay una corrida HLJ activa para cancelar."
        return
      end

      run.cancel!
      redirect_to discovery_admin_supplier_catalog_items_path, notice: "Corrida HLJ cancelada."
    end

    def show
      @sources = @supplier_catalog_item.supplier_catalog_sources.order(:source)
      @recent_runs = SupplierSyncRun.where(supplier_catalog_item: @supplier_catalog_item).recent.limit(10)
      prepare_linking_analysis
    end

    def search
      q = params[:query].to_s.strip
      return render json: [] if q.blank? || q.length < 2

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
      items = SupplierCatalogItem
              .where("LOWER(canonical_name) LIKE ? OR LOWER(external_sku) LIKE ?", pattern, pattern)
              .order(:canonical_name)
              .limit(20)

      render json: items.map { |item|
        {
          id: item.id,
          canonical_name: item.canonical_name,
          external_sku: item.external_sku,
          canonical_status: item.canonical_status,
          main_image_url: item.main_image_url,
          linked: item.product_id.present?
        }
      }
    end

    def prepare_catalog_view
      @q = params[:q].to_s.strip
      @status = params[:status].to_s.strip
      @link_filter = params[:linked].to_s.strip
      @dup_sku_filter = params[:dup_sku].to_s.strip
      @disc_filter = params[:hide_discontinued].to_s.strip
      @sort = params[:sort].to_s.strip

      scope = SupplierCatalogItem.includes(:product, :supplier_catalog_sources).recently_seen
      scope = scope.where("LOWER(canonical_name) LIKE ? OR LOWER(external_sku) LIKE ? OR LOWER(barcode) LIKE ?", term, term, term) if @q.present?
      scope = scope.where(canonical_status: @status) if @status.present?
      scope = scope.linked if @link_filter == "yes"
      scope = scope.unlinked if @link_filter == "no"

      if @dup_sku_filter == "yes"
        dup_skus = Product.where.not(supplier_product_code: [nil, ""])
                         .group(:supplier_product_code)
                         .having("COUNT(*) > 1")
                         .pluck(:supplier_product_code)
        scope = scope.where(external_sku: dup_skus)
      end

      if @disc_filter == "yes"
        scope = scope.where.not(canonical_status: "discontinued")
        discontinued_ids = Product.where(discontinued: true).pluck(:id)
        scope = scope.where.not(product_id: discontinued_ids) if discontinued_ids.any?
      end

      if @sort == "similarity"
        # Load all linked items, sort by similarity ascending, then paginate
        all_items = scope.linked.to_a.select { |i| i.product.present? }
          .sort_by { |i| helpers.name_similarity_score(i.canonical_name, i.product.product_name) }
        @supplier_catalog_items = Kaminari.paginate_array(all_items).page(params[:page]).per(25)
      else
        @supplier_catalog_items = scope.page(params[:page]).per(25)
      end

      @status_options = SupplierCatalogItem.distinct.order(:canonical_status).pluck(:canonical_status).compact
      @recent_runs = SupplierSyncRun.recent.limit(10)
      @counts = {
        total: SupplierCatalogItem.count,
        linked: SupplierCatalogItem.linked.count,
        unlinked: SupplierCatalogItem.unlinked.count,
        future_release: SupplierCatalogItem.future_release.count
      }
    end

    def prepare_discovery_view
      @active_discovery_run = active_discovery_run
      @discovery_preset_options = HLJ_DISCOVERY_PRESETS.map { |key, config| [config[:label], key] }
      @maker_options = Suppliers::Hlj::SearchQuery::MAKER_OPTIONS
      @genre_options = Suppliers::Hlj::SearchQuery::GENRE_OPTIONS
      @scale_options = Suppliers::Hlj::SearchQuery::SCALE_OPTIONS
      @discovery_form = discovery_form_defaults
      @recent_runs = SupplierSyncRun.recent.limit(10)
    end

    def create_product
      catalog = @supplier_catalog_item

      product = Product.new(
        product_sku: catalog.external_sku,
        product_name: catalog.canonical_name,
        brand: catalog.canonical_brand.presence || "HLJ",
        category: catalog.canonical_category.presence || "diecast",
        status: "draft",
        selling_price: catalog.canonical_price.presence || 1,
        minimum_price: catalog.canonical_price.presence || 1,
        maximum_discount: 0,
        reorder_point: 0
      )

      ActiveRecord::Base.transaction do
        product.save!
        catalog.update!(product: product)
      end

      redirect_to review_sync_admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Producto creado y vinculado. Revisa los campos a sincronizar."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al crear producto: #{e.message}"
    end

    def link_product
      product = Product.find_by_identifier!(params[:product_identifier])
      @supplier_catalog_item.update!(product: product)

      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Producto vinculado correctamente."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Producto no encontrado con ese identificador."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al vincular producto: #{e.message}"
    end

    def unlink_product
      @supplier_catalog_item.update!(product_id: nil)
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Producto desvinculado."
    end

    def clear_product_sku
      product = Product.find(params[:product_id])
      product.update!(supplier_product_code: nil)
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "SKU proveedor eliminado de \"#{product.product_name}\"."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Producto no encontrado."
    end

    def sync_product
      if @supplier_catalog_item.product.blank?
        redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Primero vincula o genera un producto."
        return
      end

      redirect_to review_sync_admin_supplier_catalog_item_path(@supplier_catalog_item)
    end

    def review_sync
      if @supplier_catalog_item.product.blank?
        redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Primero vincula un producto."
        return
      end

      @product = @supplier_catalog_item.product
      build_review_sync_data
    end

    def apply_sync
      if @supplier_catalog_item.product.blank?
        redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Primero vincula un producto."
        return
      end

      product = @supplier_catalog_item.product
      selected = Array(params[:sync_fields])
      catalog = @supplier_catalog_item
      parsed_dims = helpers.parse_catalog_dimensions(catalog.details_payload)
      applied_count = 0

      ActiveRecord::Base.transaction do
        if selected.include?("barcode") && catalog.barcode.present?
          product.barcode = catalog.barcode
          applied_count += 1
        end
        if selected.include?("supplier_product_code") && catalog.supplier_product_code.present?
          product.supplier_product_code = catalog.supplier_product_code
          applied_count += 1
        end
        if selected.include?("launch_date") && catalog.canonical_release_date.present?
          product.launch_date = catalog.canonical_release_date
          applied_count += 1
        end
        if selected.include?("weight_gr") && parsed_dims[:weight_gr].present?
          product.weight_gr = parsed_dims[:weight_gr]
          applied_count += 1
        end
        if selected.include?("length_cm") && parsed_dims[:length_cm].present?
          product.length_cm = parsed_dims[:length_cm]
          applied_count += 1
        end
        if selected.include?("width_cm") && parsed_dims[:width_cm].present?
          product.width_cm = parsed_dims[:width_cm]
          applied_count += 1
        end
        if selected.include?("height_cm") && parsed_dims[:height_cm].present?
          product.height_cm = parsed_dims[:height_cm]
          applied_count += 1
        end

        # Individual image additions
        add_urls = Array(params[:add_images]).select(&:present?)
        add_urls.each do |url|
          downloaded = URI.open(url) # rubocop:disable Security/Open
          filename = File.basename(URI.parse(url).path)
          product.product_images.attach(io: downloaded, filename: filename, content_type: downloaded.content_type)
          applied_count += 1
        rescue StandardError => e
          Rails.logger.warn("[SyncImages] Failed to download #{url}: #{e.message}")
        end

        # Individual image removals
        remove_ids = Array(params[:remove_images]).map(&:to_i).select(&:positive?)
        remove_ids.each do |blob_id|
          attachment = product.product_images.find { |a| a.blob_id == blob_id }
          if attachment
            attachment.purge_later
            applied_count += 1
          end
        end

        product.save!
      end

      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Sincronización aplicada (#{applied_count} cambios)."
    rescue StandardError => e
      redirect_to review_sync_admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al sincronizar: #{e.message}"
    end

    def refresh_hlj
      Suppliers::Hlj::RefreshItemService.new(@supplier_catalog_item).call
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Artículo actualizado desde HLJ."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al refrescar HLJ: #{e.message}"
    end

    def refresh_takara_tomy_mall
      Suppliers::TakaraTomyMall::BackfillItemService.new(@supplier_catalog_item).call
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Fuente Takara Tomy Mall actualizada."
    rescue Faraday::TimeoutError, Net::ReadTimeout, Net::OpenTimeout => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item),
        alert: "Takara Tomy Mall no respondió (timeout). El sitio bloquea conexiones desde servidores cloud. Intenta la actualización masiva desde un entorno local."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al refrescar Takara Tomy Mall: #{e.message}"
    end

    def refresh_tomica_fandom
      Suppliers::TomicaFandom::BackfillItemService.new(@supplier_catalog_item).call
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Fuente Tomica Fandom actualizada."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al refrescar Tomica Fandom: #{e.message}"
    end

    private

    def set_supplier_catalog_item
      @supplier_catalog_item = SupplierCatalogItem.find(params[:id])
    end

    def term
      "%#{@q.downcase}%"
    end

    def discovery_form_defaults
      {
        preset: params[:preset].presence || "all",
        word: params[:word].to_s,
        makers: array_param(:makers),
        genre_codes: array_param(:genre_codes),
        scales: array_param(:scales),
        series: params[:series].to_s,
        date_added_within_days: integer_param(:date_added_within_days),
        date_arrivals_within_days: integer_param(:date_arrivals_within_days),
        max_pages: params[:max_pages].presence,
        max_items: params[:max_items].presence
      }
    end

    def discovery_options_from_params
      preset_key = params[:preset].presence || "all"
      preset = HLJ_DISCOVERY_PRESETS.fetch(preset_key, HLJ_DISCOVERY_PRESETS.fetch("all"))
      mode = params[:discovery_mode] == "test" ? "manual_test" : "manual_discovery"

      max_pages = integer_param(:max_pages)
      max_items = integer_param(:max_items)
      max_pages = 1 if mode == "manual_test" && max_pages.nil?
      max_items = 5 if mode == "manual_test" && max_items.nil?

      {
        mode: mode,
        preset: preset_key,
        word: params[:word].presence || preset[:word],
        makers: array_param(:makers).presence || preset[:makers],
        genre_codes: array_param(:genre_codes).presence || preset[:genre_codes],
        scales: array_param(:scales).presence || preset[:scales],
        series: params[:series].presence || preset[:series],
        review_feed: preset[:review_feed],
        date_added_within_days: integer_param(:date_added_within_days) || preset[:date_added_within_days],
        date_arrivals_within_days: integer_param(:date_arrivals_within_days) || preset[:date_arrivals_within_days],
        max_pages: max_pages,
        max_items: max_items,
        fetch_detail: true
      }.compact_blank
    end

    def parsed_makers
      params[:makers].to_s.split(/\s*,\s*|\n+/).map(&:strip).reject(&:blank?)
    end

    def array_param(key)
      value = params[key]
      return Array(value).compact_blank if value.is_a?(Array)

      value.to_s.split(/\s*,\s*|\n+/).map(&:strip).reject(&:blank?)
    end

    def integer_param(key)
      value = params[key].to_s.strip
      return nil if value.blank?

      value.to_i.positive? ? value.to_i : nil
    end

    def discovery_notice(options)
      label = options[:mode] == "manual_test" ? "Prueba HLJ encolada" : "Descubrimiento HLJ encolado"
      filters = []
      filters << "preset #{options[:preset]}" if options[:preset].present?
      filters << "word=#{options[:word]}" if options[:word].present?
      filters << "makers=#{Array(options[:makers]).join(' / ')}" if Array(options[:makers]).any?
      filters << "categoría=#{Array(options[:genre_codes]).join(' / ')}" if Array(options[:genre_codes]).any?
      filters << "escala=#{Array(options[:scales]).join(' / ')}" if Array(options[:scales]).any?
      filters << "serie=#{options[:series]}" if options[:series].present?
      filters << "agregados=#{options[:date_added_within_days]} días" if options[:date_added_within_days].present?
      filters << "arrivals=#{options[:date_arrivals_within_days]} días" if options[:date_arrivals_within_days].present?
      filters << "páginas=#{options[:max_pages]}" if options[:max_pages].present?
      filters << "productos=#{options[:max_items]}" if options[:max_items].present?

      [label, filters.join(" · ")].reject(&:blank?).join(": ")
    end

    def active_discovery_run
      SupplierSyncRun.cancel_stale!
      SupplierSyncRun.genuinely_active.where(source: "hlj").order(created_at: :desc).first
    end

    def prepare_linking_analysis
      catalog_name = @supplier_catalog_item.canonical_name.to_s

      # Name similarity warning for linked products
      if @supplier_catalog_item.product.present?
        product_name = @supplier_catalog_item.product.product_name.to_s
        @name_similarity = helpers.name_similarity_score(catalog_name, product_name)
        @name_mismatch = @name_similarity < 0.3
      end

      # Products matching by supplier_product_code (same SKU)
      sku = @supplier_catalog_item.external_sku
      if sku.present?
        @sku_matching_products = Product.where(supplier_product_code: sku)
        @sku_matching_products = @sku_matching_products.or(Product.where(supplier_product_code: sku.upcase)) if sku != sku.upcase
      else
        @sku_matching_products = Product.none
      end

      # Candidate products by name keywords
      keywords = extract_keywords(catalog_name)
      if keywords.any?
        conditions = keywords.map { "LOWER(product_name) LIKE ?" }
        values = keywords.map { |kw| "%#{sanitize_sql_like(kw.downcase)}%" }
        scope = Product.where(conditions.join(" OR "), *values)
        scope = scope.where.not(id: @supplier_catalog_item.product_id) if @supplier_catalog_item.product_id.present?
        @candidate_products = scope.limit(10)
      else
        @candidate_products = Product.none
      end
    end

    def extract_keywords(name)
      name.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split.select { |w| w.length >= 3 }.uniq.first(6)
    end

    def sanitize_sql_like(string)
      string.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end

    def build_review_sync_data
      catalog = @supplier_catalog_item
      product = @product
      parsed_dims = helpers.parse_catalog_dimensions(catalog.details_payload)

      # Syncable fields — these have checkboxes
      @syncable_fields = []
      @syncable_fields << { key: "barcode", label: "Barcode", catalog_val: catalog.barcode, product_val: product.barcode, different: catalog.barcode.present? && catalog.barcode != product.barcode }
      @syncable_fields << { key: "supplier_product_code", label: "Código proveedor", catalog_val: catalog.supplier_product_code, product_val: product.supplier_product_code, different: catalog.supplier_product_code.present? && catalog.supplier_product_code != product.supplier_product_code }
      @syncable_fields << { key: "launch_date", label: "Fecha lanzamiento", catalog_val: catalog.canonical_release_date&.to_s, product_val: product.launch_date&.to_s, different: catalog.canonical_release_date.present? && catalog.canonical_release_date.to_s != product.launch_date.to_s }
      @syncable_fields << { key: "weight_gr", label: "Peso (g)", catalog_val: parsed_dims[:weight_gr]&.to_s, product_val: product.weight_gr&.to_s, different: parsed_dims[:weight_gr].present? && parsed_dims[:weight_gr] != product.weight_gr&.to_f }
      @syncable_fields << { key: "length_cm", label: "Largo (cm)", catalog_val: parsed_dims[:length_cm]&.to_s, product_val: product.length_cm&.to_s, different: parsed_dims[:length_cm].present? && parsed_dims[:length_cm] != product.length_cm&.to_f }
      @syncable_fields << { key: "width_cm", label: "Ancho (cm)", catalog_val: parsed_dims[:width_cm]&.to_s, product_val: product.width_cm&.to_s, different: parsed_dims[:width_cm].present? && parsed_dims[:width_cm] != product.width_cm&.to_f }
      @syncable_fields << { key: "height_cm", label: "Alto (cm)", catalog_val: parsed_dims[:height_cm]&.to_s, product_val: product.height_cm&.to_s, different: parsed_dims[:height_cm].present? && parsed_dims[:height_cm] != product.height_cm&.to_f }

      # Reference-only fields — informational, no sync
      similarity = helpers.name_similarity_score(catalog.canonical_name, product.product_name)
      catalog_price = catalog.currency == "JPY" ? "¥#{catalog.canonical_price.to_i}" : catalog.canonical_price.to_s

      @reference_fields = []
      @reference_fields << { label: "Nombre", catalog_val: catalog.canonical_name, product_val: product.product_name, similarity: similarity }
      @reference_fields << { label: "Marca", catalog_val: catalog.canonical_brand, product_val: product.brand }
      @reference_fields << { label: "Categoría", catalog_val: catalog.canonical_category, product_val: product.category }
      @reference_fields << { label: "Precio", catalog_val: catalog_price, product_val: "$#{product.selling_price}" }
      @reference_fields << { label: "Descripción", catalog_val: catalog.description_raw.to_s.truncate(200), product_val: product.description.to_s.truncate(200) }

      # Images — individual selection
      @catalog_images = Array(catalog.image_urls).select(&:present?)
      @product_images = product.product_images.to_a
    end
  end
end