
# app/models/inventory_item.rb
class InventoryItem < ApplicationRecord
  belongs_to :user
  belongs_to :location, optional: true
  belongs_to :shop

  has_many :item_inventories, dependent: :destroy
  has_many :items, through: :item_inventories

  validates :name, presence: true, uniqueness: { scope: [:user_id, :location_id], case_sensitive: false }
  validates :shop, presence: true
  validate :location_belongs_to_user
  validate :shop_belongs_to_user

  private

  def location_belongs_to_user
    validate_associated_user(:location)
  end

  def shop_belongs_to_user
    validate_associated_user(:shop)
  end
end
