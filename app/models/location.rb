
# app/models/location.rb
class Location < ApplicationRecord
  has_many :inventory_items, dependent: :restrict_with_exception
  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
