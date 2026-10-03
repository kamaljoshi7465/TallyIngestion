class CreateImports < ActiveRecord::Migration[8.0]
  def change
    create_table :imports do |t|
      t.string :content_hash, null: false
      t.string :document_type, null: false
      t.string :status, null: false
      t.string :detected_encoding
      t.jsonb :warnings, default: []
      t.jsonb :error_messages, default: []
      t.text :raw_source

      t.timestamps
    end

    add_index :imports, :content_hash, unique: true
  end
end
