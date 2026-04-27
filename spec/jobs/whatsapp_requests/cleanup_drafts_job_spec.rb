require 'rails_helper'

RSpec.describe WhatsappRequests::CleanupDraftsJob, type: :job do
  it 'removes drafts older than the cutoff' do
    fresh = create(:whatsapp_request, status: :draft, updated_at: 10.days.ago)
    stale = create(:whatsapp_request, status: :draft, updated_at: 40.days.ago)
    sent_old = create(:whatsapp_request, status: :sent, updated_at: 90.days.ago, code: 'WA-2099-9999')

    expect { described_class.perform_now }.to change(WhatsappRequest, :count).by(-1)

    expect { fresh.reload }.not_to raise_error
    expect { sent_old.reload }.not_to raise_error
    expect(WhatsappRequest.exists?(stale.id)).to be(false)
  end

  it 'accepts a custom age threshold' do
    create(:whatsapp_request, status: :draft, updated_at: 5.days.ago)
    create(:whatsapp_request, status: :draft, updated_at: 9.days.ago)

    expect { described_class.perform_now(age_days: 7) }.to change(WhatsappRequest, :count).by(-1)
  end
end
