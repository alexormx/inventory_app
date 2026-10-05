# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupPhotoPurgeJob do
  def lookup_created(at)
    travel_to(at) do
      Collectibles::AiLookup.new(user: create(:user, :admin)).tap do |l|
        l.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
        l.save!
      end
    end
  end

  it 'purga la foto de búsquedas con más de 7 días y conserva el registro' do
    old = lookup_created(8.days.ago)
    recent = lookup_created(2.days.ago)

    described_class.perform_now

    expect(old.reload.photos).not_to be_attached
    expect(Collectibles::AiLookup.exists?(old.id)).to be(true)
    expect(recent.reload.photos).to be_attached
  end
end
