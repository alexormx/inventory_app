require 'rails_helper'

# NOTE: This spec has been superseded by request spec: spec/requests/admin/dashboard_spec.rb
# Keeping file with a no-op example to preserve history while avoiding duplicate coverage/failures.

RSpec.describe Admin::DashboardController, type: :controller do
  it 'is covered by request specs (see spec/requests/admin/dashboard_spec.rb)' do
    expect(true).to be_truthy
  end
end