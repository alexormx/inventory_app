require 'rails_helper'

RSpec.describe Product, type: :model do
  it "defaults to draft" do
    p = Product.new(product_sku: "X1", product_name: "Test", selling_price: 10, maximum_discount: 0, minimum_price: 0, whatsapp_code: "W1")
    p.validate
    expect(p.status).to eq("draft")
  end

  it "normalizes case" do
    p = Product.new(product_sku: "X2", product_name: "Test", selling_price: 10, maximum_discount: 0, minimum_price: 0, whatsapp_code: "W2", status: "Active")
    p.validate
    expect(p.status).to eq("active")
  end

  it "rejects unknown status values" do
    expect {
      Product.new(product_sku: "X3", product_name: "Test", selling_price: 10, maximum_discount: 0, minimum_price: 0, whatsapp_code: "W3", status: "weird")
    }.to raise_error(ArgumentError, /'weird' is not a valid status/)
  end
end
