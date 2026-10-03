class Import < ApplicationRecord
  has_many :vouchers, dependent: :destroy

  validates :content_hash, presence: true, uniqueness: true
end