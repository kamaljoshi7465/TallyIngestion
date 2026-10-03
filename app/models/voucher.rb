class Voucher < ApplicationRecord
  belongs_to :import

  has_many :ledger_entries, dependent: :destroy
  has_many :inventory_entries, dependent: :destroy
end