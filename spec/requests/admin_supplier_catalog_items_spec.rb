require 'rails_helper'

RSpec.describe "Admin::SupplierCatalogItems", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }
  let!(:catalog_item) { create(:supplier_catalog_item) }

  before do
    login_as(admin, scope: :user)
  end

  describe "GET /admin/supplier_catalog_items" do
    it "renders the index" do
      get admin_supplier_catalog_items_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Actualización y enriquecimiento del catálogo")
      expect(response.body).to include(catalog_item.canonical_name)
      expect(response.body).not_to include("Vista previa HLJ")
    end

    it "links to the discovery page" do
      get admin_supplier_catalog_items_path

      expect(response.body).to include("Ir a descubrir nuevos productos")
    end
  end

  describe "GET /admin/supplier_catalog_items/discovery" do
    it "renders the discovery page with step-based flow" do
      get discovery_admin_supplier_catalog_items_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Descubrir nuevos productos en HLJ")
      expect(response.body).to include("Consultar vista previa")
      expect(response.body).to include("Configura filtros")
      expect(response.body).not_to include(catalog_item.canonical_name)
      expect(response.body).not_to include("Corrida en progreso")
    end

    it "shows progress and stop/cancel when a discovery run is genuinely active" do
      create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "running", started_at: Time.current)

      get discovery_admin_supplier_catalog_items_path

      expect(response.body).to include("Corrida en progreso")
      expect(response.body).to include("Solicitar detención")
      expect(response.body).to include("Cancelar")
    end

    it "does not show stale runs as active" do
      create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "running",
             started_at: 2.hours.ago, created_at: 2.hours.ago, updated_at: 2.hours.ago)

      get discovery_admin_supplier_catalog_items_path

      expect(response.body).not_to include("Corrida en progreso")
    end
  end

  describe "GET /admin/supplier_catalog_items/discovery_progress" do
    it "renders the progress bar for the active run" do
      run = create(
        :supplier_sync_run,
        source: "hlj",
        mode: "manual_discovery",
        status: "running",
        started_at: Time.current,
        processed_count: 4,
        created_count: 3,
        updated_count: 1,
        metadata: {
          "progress_total_items" => 10,
          "progress_current_page" => 1,
          "progress_page_item_index" => 4,
          "progress_page_item_count" => 10
        }
      )

      get discovery_progress_admin_supplier_catalog_items_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Progreso del descubrimiento HLJ")
      expect(response.body).to include("40%")
      expect(response.body).to include(run.progress_label)
    end
  end

  describe "POST /admin/supplier_catalog_items/stop_discovery" do
    it "requests stop for the active hlj discovery run" do
      run = create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "running", started_at: Time.current, metadata: {})

      post stop_discovery_admin_supplier_catalog_items_path

      expect(response).to redirect_to(discovery_admin_supplier_catalog_items_path)
      expect(run.reload.metadata["stop_requested"]).to be true
    end
  end

  describe "POST /admin/supplier_catalog_items/run_discovery" do
    it "enqueues a filtered HLJ test run" do
      allow(Suppliers::Hlj::WeeklyDiscoveryJob).to receive(:perform_later)

      post run_discovery_admin_supplier_catalog_items_path, params: {
        discovery_mode: "test",
        preset: "takara_cars",
        word: "tomica",
        makers: ["Takara Tomy", "Tomy", "Tomytec"],
        genre_codes: ["Cars & Bikes"],
        max_pages: "3",
        max_items: "7"
      }

      expect(response).to redirect_to(discovery_admin_supplier_catalog_items_path)
      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_later).with(
        mode: "manual_test",
        preset: "takara_cars",
        word: "tomica",
        makers: ["Takara Tomy", "Tomy", "Tomytec"],
        genre_codes: ["Cars & Bikes"],
        max_pages: 3,
        max_items: 7,
        fetch_detail: true
      )
    end

    it "uses test defaults when limits are omitted" do
      allow(Suppliers::Hlj::WeeklyDiscoveryJob).to receive(:perform_later)

      post run_discovery_admin_supplier_catalog_items_path, params: {
        discovery_mode: "test",
        preset: "tomica"
      }

      expect(response).to redirect_to(discovery_admin_supplier_catalog_items_path)
      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_later).with(
        mode: "manual_test",
        preset: "tomica",
        word: "tomica",
        max_pages: 1,
        max_items: 5,
        fetch_detail: true
      )
    end
  end

  describe "POST /admin/supplier_catalog_items/preview_discovery" do
    it "renders a preview without creating supplier catalog records" do
      preview = Suppliers::Hlj::PreviewDiscoveryService::Result.new(
        total_found: 24,
        sample_items: [
          {
            name: "No.43 Lamborghini Temerario",
            external_sku: "TKT95078",
            source_url: "https://www.hlj.com/no-43-lamborghini-temerario-tkt95078",
            listing_price_text: "$74.29 MXN",
            listing_image_url: "https://www.hlj.com/productimages/tkt/tkt95078_0.jpg"
          }
        ],
        scanned_pages: 2,
        available_pages: 5,
        sample_limit: 16
      )

      service = instance_double(Suppliers::Hlj::PreviewDiscoveryService, call: preview)
      allow(Suppliers::Hlj::PreviewDiscoveryService).to receive(:new).and_return(service)

      expect do
        post preview_discovery_admin_supplier_catalog_items_path, params: {
          preset: "tomica",
          max_pages: "2"
        }
      end.not_to change(SupplierCatalogItem, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vista previa")
      expect(response.body).to include("24")
      expect(response.body).to include("No.43 Lamborghini Temerario")
      expect(response.body).to include("Ejecutar descubrimiento completo")
    end
  end

  describe "POST /admin/supplier_catalog_items/cancel_discovery" do
    it "cancels the active discovery run" do
      run = create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "running", started_at: Time.current, metadata: {})

      post cancel_discovery_admin_supplier_catalog_items_path

      expect(response).to redirect_to(discovery_admin_supplier_catalog_items_path)
      expect(run.reload.status).to eq("cancelled")
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/create_product" do
    it "creates and links a product" do
      expect do
        post create_product_admin_supplier_catalog_item_path(catalog_item)
      end.to change(Product, :count).by(1)

      expect(response).to redirect_to(review_sync_admin_supplier_catalog_item_path(catalog_item))
      expect(catalog_item.reload.product).to be_present
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/link_product" do
    it "links an existing product by identifier" do
      product = create(:product, skip_seed_inventory: true)

      post link_product_admin_supplier_catalog_item_path(catalog_item), params: { product_identifier: product.product_sku }

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(catalog_item.reload.product).to eq(product)
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/refresh_takara_tomy_mall" do
    it "enqueues a background job and redirects" do
      expect {
        post refresh_takara_tomy_mall_admin_supplier_catalog_item_path(catalog_item)
      }.to have_enqueued_job(Suppliers::RefreshSourceJob).with(catalog_item.id, "takaratomy_mall")

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/refresh_tomica_fandom" do
    it "enqueues a background job and redirects" do
      expect {
        post refresh_tomica_fandom_admin_supplier_catalog_item_path(catalog_item)
      }.to have_enqueued_job(Suppliers::RefreshSourceJob).with(catalog_item.id, "tomica_fandom")

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
    end
  end
end