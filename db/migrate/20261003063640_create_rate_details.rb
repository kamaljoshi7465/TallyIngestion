class CreateRateDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_details do |t|
      t.references :rateable, polymorphic: true, null: false

      t.integer :position, null: false
      t.string :duty_head
      t.string :rate

      t.timestamps
    end

    add_index :rate_details, [:rateable_type, :rateable_id, :position],
              name: "index_rate_details_on_rateable_and_position"
  end
end