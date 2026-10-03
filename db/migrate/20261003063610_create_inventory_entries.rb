class CreateInventoryEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_entries do |t|
      t.references :voucher, null: false, foreign_key: true

      t.integer :position, null: false
      t.string :source_tag, null: false
      t.string :stock_item_name
      t.string :is_deemed_positive
      t.string :actual_qty
      t.string :billed_qty
      t.string :rate
      t.string :amount

      t.timestamps
    end

    add_index :inventory_entries, [:voucher_id, :position]
  end
end