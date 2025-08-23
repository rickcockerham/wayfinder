class ItemBlock < ApplicationRecord
  belongs_to :blocker, class_name: "Item"
  belongs_to :blocked, class_name: "Item"

  validates :blocker_id, :blocked_id, presence: true
  validates :blocked_id, uniqueness: { scope: :blocker_id } # no dup edges
end
