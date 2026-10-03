class CreateBillAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :bill_allocations do |t|
      t.references :ledger_entry, null: false, foreign_key: true

      t.integer :position, null: false
      t.string :name
      t.string :bill_type
      t.string :amount

      t.timestamps
    end

    add_index :bill_allocations, [:ledger_entry_id, :position]
  end
end