class CreateLedgerEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :ledger_entries do |t|
      t.references :voucher, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :source_tag, null: false
      t.string :ledger_name
      t.string :is_deemed_positive
      t.string :amount

      t.timestamps
    end
  end
end
