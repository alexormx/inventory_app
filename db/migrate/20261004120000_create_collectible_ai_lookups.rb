# frozen_string_literal: true

class CreateCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :collectible_ai_lookups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.jsonb :result
      t.text :error_message
      t.string :ai_model
      t.integer :tokens_input
      t.integer :tokens_output
      t.integer :web_search_calls
      t.integer :estimated_cost_cents
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :collectible_ai_lookups, :created_at
  end
end
