require 'rails_helper'

RSpec.describe 'Visitor tracking', type: :request do
  include ActiveJob::TestHelper

  it 'creates a log entry on page visit' do
    # El tracking se encola como job async (VisitorLogs::TrackJob); hay que
    # ejecutarlo para que el VisitorLog se materialice.
    expect {
      perform_enqueued_jobs { get root_path }
    }.to change(VisitorLog, :count).by(1)
  end
end
