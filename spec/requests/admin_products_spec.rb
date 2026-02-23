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
      expect(response).to redirect_to(admin_products_path)
    end
  end

  describe "DELETE /admin/products/:id/images/:image_id" do
    it "purges one image and redirects to edit in HTML" do
      image = product.product_images.first
      expect(image).to be_present

      expect do
        delete admin_product_purge_image_path(product, image_id: image.id)
      end.to change(ActiveStorage::Attachment, :count).by(-1)

      expect(response).to redirect_to(edit_admin_product_path(product))
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