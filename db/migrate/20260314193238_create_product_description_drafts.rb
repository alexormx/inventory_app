class CreateProductDescriptionDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :product_description_drafts do |t|
      t.references :product, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.text :draft_content
      t.jsonb :draft_attributes, default: {}
      t.text :original_description
      t.jsonb :original_attributes, default: {}
      t.jsonb :structured_output, default: {}
      t.jsonb :warnings, default: []
      t.jsonb :source_snapshot, default: {}
      t.decimal :confidence_score, precision: 3, scale: 2
      t.string :ai_provider
      t.string :ai_model
      t.string :prompt_version
      t.text :prompt_used
      t.integer :tokens_input
      t.integer :tokens_output
      t.integer :estimated_cost_cents
      t.text :error_message
      t.datetime :generated_at
      t.datetime :published_at
      t.references :published_by, foreign_key: { to_table: :users }
      t.text :admin_notes

      t.timestamps
    end

    add_index :product_description_drafts, [:product_id, :status]
    add_index :product_description_drafts, :status
    add_index :product_description_drafts, :created_at
  end
end
