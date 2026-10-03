class CreateBankAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :bank_allocations do |t|
      t.references :ledger_entry, null: false, foreign_key: true

      t.integer :position, null: false
      t.string :date
      t.string :name
      t.string :transaction_type
      t.string :amount

      t.timestamps
    end

    add_index :bank_allocations, [:ledger_entry_id, :position]
  end
end