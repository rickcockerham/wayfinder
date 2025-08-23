
# app/models/shop.rb
class Shop < ApplicationRecord
  has_many :material_requirements, dependent: :nullify
  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
