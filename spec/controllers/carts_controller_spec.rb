require 'rails_helper'

RSpec.describe CartsController, type: :controller do
  describe "GET #show" do
    it "renders the cart page" do
      get :show
      expect(response).to have_http_status(:success)
    end
  end
end
