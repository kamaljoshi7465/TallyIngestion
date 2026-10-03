class AddTallyResponseToImports < ActiveRecord::Migration[8.0]
  def change
    add_column :imports, :tally_response, :jsonb
  end
end
