# frozen_string_literal: true

module Admin
  class SupplierCatalogItemsController < ApplicationController
    HLJ_DISCOVERY_PRESETS = {
      "all" => {
        label: "Todo HLJ",
        word: nil,
        makers: [],
        genre_code: nil
      },
      "tomica" => {
        label: "Solo Tomica",
        word: "tomica",
        makers: [],
        genre_code: nil
      },
      "takara_cars" => {
        label: "Tomica/Takara solo coches",
        word: nil,
        makers: ["Takara Tomy", "Tomy", "Tomytec", "Takara Tomy A.R.T.S"],
        genre_code: "Cars & Bikes"
      }
    }.freeze

    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_supplier_catalog_item, only: [:show, :create_product, :link_product, :sync_product, :refresh_hlj, :refresh_takara_tomy_mall, :refresh_tomica_fandom]

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
        genre_code: options[:genre_code]
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
    end

    def prepare_catalog_view
      @q = params[:q].to_s.strip
      @status = params[:status].to_s.strip
      @link_filter = params[:linked].to_s.strip

      scope = SupplierCatalogItem.includes(:product, :supplier_catalog_sources).recently_seen
      scope = scope.where("LOWER(canonical_name) LIKE ? OR LOWER(external_sku) LIKE ? OR LOWER(barcode) LIKE ?", term, term, term) if @q.present?
      scope = scope.where(canonical_status: @status) if @status.present?
      scope = scope.linked if @link_filter == "yes"
      scope = scope.unlinked if @link_filter == "no"

      @supplier_catalog_items = scope.page(params[:page]).per(25)
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
      @discovery_form = discovery_form_defaults
      @recent_runs = SupplierSyncRun.recent.limit(10)
    end

    def create_product
      result = Suppliers::Catalog::SyncProductService.new(@supplier_catalog_item).call
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: result.created ? "Producto creado y vinculado." : "Producto existente vinculado correctamente."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al crear/vincular producto: #{e.message}"
    end

    def link_product
      product = Product.find_by_identifier!(params[:product_identifier])
      @supplier_catalog_item.update!(product: product)
      Suppliers::Catalog::SyncProductService.new(@supplier_catalog_item, product: product).call

      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Producto vinculado correctamente."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Producto no encontrado con ese identificador."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al vincular producto: #{e.message}"
    end

    def sync_product
      if @supplier_catalog_item.product.blank?
        redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Primero vincula o genera un producto."
        return
      end

      Suppliers::Catalog::SyncProductService.new(@supplier_catalog_item, product: @supplier_catalog_item.product, force_full_update: true).call
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), notice: "Producto sincronizado con datos del catálogo proveedor."
    rescue StandardError => e
      redirect_to admin_supplier_catalog_item_path(@supplier_catalog_item), alert: "Error al sincronizar producto: #{e.message}"
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
        makers: params[:makers].to_s,
        genre_code: params[:genre_code].to_s,
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
        makers: parsed_makers.presence || preset[:makers],
        genre_code: params[:genre_code].presence || preset[:genre_code],
        max_pages: max_pages,
        max_items: max_items,
        fetch_detail: true
      }.compact
    end

    def parsed_makers
      params[:makers].to_s.split(/\s*,\s*|\n+/).map(&:strip).reject(&:blank?)
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
      filters << "género=#{options[:genre_code]}" if options[:genre_code].present?
      filters << "páginas=#{options[:max_pages]}" if options[:max_pages].present?
      filters << "productos=#{options[:max_items]}" if options[:max_items].present?

      [label, filters.join(" · ")].reject(&:blank?).join(": ")
    end

    def active_discovery_run
      SupplierSyncRun.cancel_stale!
      SupplierSyncRun.genuinely_active.where(source: "hlj").order(created_at: :desc).first
    end
  end
end