require 'rails_helper'

RSpec.describe 'Visitor tracking', type: :request do
  it 'creates a log entry on page visit' do
    expect {
      get root_path
    }.to change(VisitorLog, :count).by(1)
  end
end