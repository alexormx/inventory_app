# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261004130100_rename_collectible_ai_lookup_photo_attachments')

RSpec.describe RenameCollectibleAiLookupPhotoAttachments do
  it 'conserva la foto de una búsqueda hecha cuando sólo había una foto' do
    lookup = Collectibles::AiLookup.new(user: create(:user, :admin))
    lookup.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
    lookup.save!
    ActiveStorage::Attachment.where(record: lookup).update_all(name: 'photo')
    expect(lookup.reload.photos).not_to be_attached

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(lookup.reload.photos).to be_attached
  end
end
