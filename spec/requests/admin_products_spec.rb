require 'rails_helper'

RSpec.describe "Admin::Products", type: :request do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: :admin) }
  let!(:product) { create(:product) }

  before do
    login_as(admin, scope: :user)
  end

  describe "PATCH /admin/products/:id/activate" do
    it "activates the product using its slug" do
  patch activate_admin_product_path(product) # HTML request (no turbo stream)
  expect(response).to have_http_status(302)
      expect(product.reload.status).to eq("active")
    end
  end

  describe "POST /admin/products" do
    it "creates product when maximum_discount comes blank by normalizing numeric fields" do
      expect do
        post admin_products_path, params: {
          product: {
            product_sku: "SKU-BLANK-DISCOUNT-#{SecureRandom.hex(3)}",
            product_name: 'Producto con descuento vacío',
            brand: 'Tomica',
            series: 'Limited Vintage',
            category: 'diecast',
            selling_price: 199.99,
            minimum_price: 120.0,
            maximum_discount: '',
            discount_limited_stock: '',
            reorder_point: ''
          }
        }
      end.to change(Product, :count).by(1)

      created = Product.order(:created_at).last
      expect(created.maximum_discount.to_d).to eq(0.to_d)
      expect(created.discount_limited_stock).to eq(0)
      expect(created.reorder_point).to eq(0)
      expect(created.series).to eq('Limited Vintage')
      expect(response).to redirect_to(admin_products_path)
    end
  end

  describe "PATCH /admin/products/:id" do
    it "renders the edit form without legacy remote submit" do
      get edit_admin_product_path(product)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-remote="true"')
      expect(response.body).to include('type="submit"')
    end

    it "updates whatsapp_code from the admin form" do
      patch admin_product_path(product), params: {
        product: {
          product_sku: product.product_sku,
          product_name: product.product_name,
          brand: product.brand,
          series: 'Tomica Premium',
          category: product.category,
          selling_price: product.selling_price,
          minimum_price: product.minimum_price,
          maximum_discount: product.maximum_discount,
          whatsapp_code: "WA-EDIT-#{SecureRandom.hex(2).upcase}"
        }
      }

      expect(response).to redirect_to(admin_product_path(product))
      expect(product.reload.whatsapp_code).to match(/\AWA-EDIT-/)
      expect(product.reload.series).to eq('Tomica Premium')
    end

    it "does not attach new images when the product update is invalid" do
      uploaded_file = fixture_file_upload('test1.png', 'image/png')

      expect do
        patch admin_product_path(product), params: {
          product: {
            product_sku: product.product_sku,
            product_name: '',
            brand: product.brand,
            category: product.category,
            selling_price: product.selling_price,
            minimum_price: product.minimum_price,
            maximum_discount: product.maximum_discount,
            whatsapp_code: product.whatsapp_code,
            product_images: [uploaded_file]
          }
        }
      end.not_to change(ActiveStorage::Attachment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "preserves the active tab when the update is invalid" do
      patch admin_product_path(product), params: {
        active_tab: 'media',
        product: {
          product_sku: product.product_sku,
          product_name: '',
          brand: product.brand,
          category: product.category,
          selling_price: product.selling_price,
          minimum_price: product.minimum_price,
          maximum_discount: product.maximum_discount,
          whatsapp_code: product.whatsapp_code
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('name="active_tab"')
      expect(response.body).to include('value="media"')
      expect(response.body).to include('No se pudo guardar el producto.')
    end
  end

  describe "PATCH /admin/products/:id/set_primary_image" do
    it "updates the primary image for the product" do
      selected_image = product.product_images.attachments.second

      patch set_primary_image_admin_product_path(product), params: { image_id: selected_image.id }

      expect(response).to redirect_to(edit_admin_product_path(product, tab: 'media'))
      expect(product.reload.primary_product_image_attachment_id).to eq(selected_image.id)
      expect(product.primary_product_image.id).to eq(selected_image.id)
    end
  end

  describe "DELETE /admin/products/:id/images/:image_id" do
    it "purges one image and redirects to edit in HTML" do
      image = product.product_images.first
      expect(image).to be_present

      expect do
        delete admin_product_purge_image_path(product, image_id: image.id)
      end.to change(ActiveStorage::Attachment, :count).by(-1)

      expect(response).to redirect_to(edit_admin_product_path(product, tab: 'media'))
    end

    it "returns turbo stream remove action when requested as turbo stream" do
      image = product.product_images.first
      expect(image).to be_present

      expect do
        delete admin_product_purge_image_path(product, image_id: image.id),
               headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }
      end.to change(ActiveStorage::Attachment, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('turbo-stream action="remove"')
      expect(response.body).to include("target=\"image_#{image.id}\"")
    end
  end
end