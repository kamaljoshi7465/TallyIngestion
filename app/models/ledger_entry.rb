class LedgerEntry < ApplicationRecord
  belongs_to :voucher

  has_many :bill_allocations, dependent: :destroy
  has_many :bank_allocations, dependent: :destroy
  has_many :rate_details, as: :rateable, dependent: :destroy
end