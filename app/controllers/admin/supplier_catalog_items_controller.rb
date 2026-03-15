# frozen_string_literal: true

module Admin
  class SupplierCatalogItemsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_supplier_catalog_item, only: [:show, :create_product, :link_product, :sync_product, :refresh_hlj, :refresh_takara_tomy_mall, :refresh_tomica_fandom]

    def index
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

    def show
      @sources = @supplier_catalog_item.supplier_catalog_sources.order(:source)
      @recent_runs = SupplierSyncRun.where(supplier_catalog_item: @supplier_catalog_item).recent.limit(10)
    end

    def run_discovery
      Suppliers::Hlj::WeeklyDiscoveryJob.perform_later
      redirect_to admin_supplier_catalog_items_path, notice: "Sincronización semanal HLJ encolada."
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
  end
end