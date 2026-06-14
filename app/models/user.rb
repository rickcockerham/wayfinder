# app/models/user.rb
class User < ApplicationRecord
  has_many :categories, dependent: :destroy
  has_many :moods, dependent: :destroy
  has_many :shops, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :inventory_items, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :item_blocks, dependent: :destroy
  has_many :material_requirements, dependent: :destroy
  has_many :item_inventories, dependent: :destroy
  has_many :schedule_entries, dependent: :destroy
  has_one :importance_setting, dependent: :destroy

  validates :name, presence: true
  validates :access_key, presence: true, uniqueness: true
end
