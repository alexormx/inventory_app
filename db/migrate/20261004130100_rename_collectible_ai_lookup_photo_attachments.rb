# frozen_string_literal: true

# La búsqueda con IA pasó de una foto (`photo`) a varias (`photos`). Las fotos
# ya subidas se renombran para que se sigan viendo y se sigan purgando.
class RenameCollectibleAiLookupPhotoAttachments < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE active_storage_attachments SET name = 'photos'
      WHERE record_type = 'Collectibles::AiLookup' AND name = 'photo'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE active_storage_attachments SET name = 'photo'
      WHERE record_type = 'Collectibles::AiLookup' AND name = 'photos'
    SQL
  end
end
