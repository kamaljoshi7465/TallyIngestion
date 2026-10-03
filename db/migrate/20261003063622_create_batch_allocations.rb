class CreateBatchAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_allocations do |t|
      t.references :inventory_entry, null: false, foreign_key: true

      t.integer :position, null: false
      t.string :godown_name
      t.string :batch_name
      t.string :actual_qty
      t.string :billed_qty
      t.string :amount

      t.timestamps
    end

    add_index :batch_allocations, [:inventory_entry_id, :position]
  end
end