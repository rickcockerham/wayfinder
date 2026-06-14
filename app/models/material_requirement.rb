
# app/models/material_requirement.rb
class MaterialRequirement < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :shop, optional: true

  before_validation :inherit_user_from_item

  validates :name, presence: true
  validate :item_belongs_to_user
  validate :shop_belongs_to_user

  private

  def inherit_user_from_item
    self.user ||= item&.user
  end

  def item_belongs_to_user
    validate_associated_user(:item)
  end

  def shop_belongs_to_user
    validate_associated_user(:shop)
  end
end
