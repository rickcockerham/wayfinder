
# app/models/location.rb
class Location < ApplicationRecord
  belongs_to :user
  has_many :inventory_items, dependent: :restrict_with_exception
  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
end
