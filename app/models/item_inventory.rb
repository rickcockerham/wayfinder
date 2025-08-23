# app/models/item_inventory.rb
class ItemInventory < ApplicationRecord
  belongs_to :item
  belongs_to :inventory_item

  validates :qty_reserved, numericality: { greater_than_or_equal_to: 0 }
end
