class CreateAccountingAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :accounting_allocations do |t|
      t.references :inventory_entry, null: false, foreign_key: true

      t.integer :position, null: false
      t.string :ledger_name
      t.string :is_deemed_positive
      t.string :amount

      t.timestamps
    end

    add_index :accounting_allocations, [:inventory_entry_id, :position]
  end
end