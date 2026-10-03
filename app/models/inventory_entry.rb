class InventoryEntry < ApplicationRecord
  belongs_to :voucher

  has_many :batch_allocations, dependent: :destroy
  has_many :accounting_allocations, dependent: :destroy
  has_many :rate_details, as: :rateable, dependent: :destroy
end