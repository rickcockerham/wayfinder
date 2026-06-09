
# app/models/shop.rb
class Shop < ApplicationRecord
  belongs_to :user
  has_many :material_requirements, dependent: :nullify
  has_many :inventory_items, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
end
