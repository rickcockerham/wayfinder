
# app/models/inventory_item.rb
class InventoryItem < ApplicationRecord
  serialize :aliases, coder: JSON, type: Array, default: []
  belongs_to :user
  belongs_to :location, optional: true
  belongs_to :shop

  has_many :item_inventories, dependent: :destroy
  has_many :items, through: :item_inventories

  validates :name, presence: true
  # Legacy null-location duplicates must remain individually recountable by ID.
  validates :name, uniqueness: { scope: [:user_id, :location_id], case_sensitive: false },
    if: -> { new_record? || will_save_change_to_name? || will_save_change_to_location_id? || will_save_change_to_user_id? }
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
