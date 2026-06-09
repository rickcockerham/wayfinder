# app/models/item_inventory.rb
class ItemInventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :inventory_item

  before_validation :inherit_user_from_item

  validates :qty_reserved, numericality: { greater_than_or_equal_to: 0 }
  validate :item_belongs_to_user
  validate :inventory_item_belongs_to_user

  private

  def inherit_user_from_item
    self.user ||= item&.user
  end

  def item_belongs_to_user
    validate_associated_user(:item)
  end

  def inventory_item_belongs_to_user
    validate_associated_user(:inventory_item)
  end
end
