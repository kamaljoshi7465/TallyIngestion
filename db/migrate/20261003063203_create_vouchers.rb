class CreateVouchers < ActiveRecord::Migration[8.0]
  def change
    create_table :vouchers do |t|
      t.references :import, null: false, foreign_key: true
      t.integer :voucher_index, null: false

      t.string :date
      t.string :voucher_type
      t.string :voucher_number
      t.string :party_ledger_name
      t.text :narration

      t.jsonb :xml_attributes, default: {}
      t.jsonb :warnings, default: []

      t.timestamps
    end
  end
end
