class ItemBlock < ApplicationRecord
  belongs_to :user
  belongs_to :blocker, class_name: "Item"
  belongs_to :blocked, class_name: "Item"

  before_validation :inherit_user_from_items

  validates :blocker_id, :blocked_id, presence: true
  validates :blocked_id, uniqueness: { scope: :blocker_id } # no dup edges
  validate :items_belong_to_user
  validate :items_share_user

  private

  def inherit_user_from_items
    self.user ||= blocker&.user || blocked&.user
  end

  def items_belong_to_user
    validate_associated_user(:blocker)
    validate_associated_user(:blocked)
  end

  def items_share_user
    return if blocker.blank? || blocked.blank?
    return if blocker.user_id == blocked.user_id

    errors.add(:blocked, "must belong to the same user as blocker")
  end
end
