class RateDetail < ApplicationRecord
  belongs_to :rateable, polymorphic: true
end
