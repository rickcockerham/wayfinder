
# app/models/inventory_item.rb
class InventoryItem < ApplicationRecord
  belongs_to :location, optional: true
  validates :name, presence: true, uniqueness: true
  has_many :item_inventories, dependent: :destroy
  has_many :items, through: :item_inventories
  belongs_to :shop
  validates :shop, presence: true
end
