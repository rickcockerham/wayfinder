# app/models/category.rb
class Category < ApplicationRecord
  has_many :items, dependent: :restrict_with_exception
  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
