require 'rails_helper'

RSpec.describe "Orders summary", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'renders summary via string id custom (SO- prefijo)' do
    order = create(:sale_order, user: user)
    get summary_order_path(order)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(order.id) # id ya es el custom string (SO-...)
  end
end
