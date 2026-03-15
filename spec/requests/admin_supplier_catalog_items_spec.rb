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
      expect(response.body).to include("Catálogo proveedor")
      expect(response.body).to include(catalog_item.canonical_name)
    end

    it "shows the stop button when a discovery run is active" do
      create(:supplier_sync_run, source: "hlj", mode: "weekly_discovery", status: "running", started_at: Time.current)

      get admin_supplier_catalog_items_path

      expect(response.body).to include("Detener descubrimiento")
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

      expect(response).to redirect_to(admin_supplier_catalog_items_path)
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
        makers: "Takara Tomy, Tomy\nTomytec",
        genre_code: "Cars & Bikes",
        max_pages: "3",
        max_items: "7"
      }

      expect(response).to redirect_to(admin_supplier_catalog_items_path)
      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_later).with(
        mode: "manual_test",
        preset: "takara_cars",
        word: "tomica",
        makers: ["Takara Tomy", "Tomy", "Tomytec"],
        genre_code: "Cars & Bikes",
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

      expect(response).to redirect_to(admin_supplier_catalog_items_path)
      expect(Suppliers::Hlj::WeeklyDiscoveryJob).to have_received(:perform_later).with(
        mode: "manual_test",
        preset: "tomica",
        word: "tomica",
        makers: [],
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
      expect(response.body).to include("Vista previa HLJ")
      expect(response.body).to include("24")
      expect(response.body).to include("No.43 Lamborghini Temerario")
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/create_product" do
    it "creates and links a product" do
      expect do
        post create_product_admin_supplier_catalog_item_path(catalog_item)
      end.to change(Product, :count).by(1)

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
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
    it "refreshes the Takara source manually" do
      service = instance_double(Suppliers::TakaraTomyMall::BackfillItemService, call: true)
      allow(Suppliers::TakaraTomyMall::BackfillItemService).to receive(:new).with(catalog_item).and_return(service)

      post refresh_takara_tomy_mall_admin_supplier_catalog_item_path(catalog_item)

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(Suppliers::TakaraTomyMall::BackfillItemService).to have_received(:new).with(catalog_item)
    end
  end

  describe "POST /admin/supplier_catalog_items/:id/refresh_tomica_fandom" do
    it "refreshes the Fandom source manually" do
      service = instance_double(Suppliers::TomicaFandom::BackfillItemService, call: true)
      allow(Suppliers::TomicaFandom::BackfillItemService).to receive(:new).with(catalog_item).and_return(service)

      post refresh_tomica_fandom_admin_supplier_catalog_item_path(catalog_item)

      expect(response).to redirect_to(admin_supplier_catalog_item_path(catalog_item))
      expect(Suppliers::TomicaFandom::BackfillItemService).to have_received(:new).with(catalog_item)
    end
  end
end