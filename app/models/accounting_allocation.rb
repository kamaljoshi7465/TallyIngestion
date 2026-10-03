class AccountingAllocation < ApplicationRecord
  belongs_to :inventory_entry

  has_many :rate_details, as: :rateable, dependent: :destroy
end