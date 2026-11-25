# app/models/location.rb
class Location < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "Location", optional: true
  has_many :children, class_name: "Location", foreign_key: :parent_id, dependent: :restrict_with_exception
  has_many :inventory_items, dependent: :restrict_with_exception
  scope :visible, -> { where(hidden: false) }
  validates :name, presence: true, length: { maximum: 255 },
    uniqueness: { scope: [:user_id, :parent_id], case_sensitive: false }
  validate :valid_parent

  #-----------------------------------------------------------------------------
  def path
    # Walk iteratively so depth is unrelated to the Ruby call stack.
    nodes = []
    seen = {}
    node = self
    while node
      raise ActiveRecord::RecordInvalid, self if seen[node.id] || node.user_id != user_id
      seen[node.id] = true
      nodes.unshift({ id: node.id, name: node.name })
      node = node.parent
    end
    nodes
  end

  #-----------------------------------------------------------------------------
  def full_name
    path.map { |node| node[:name] }.join(" → ")
  end

  private

  #-----------------------------------------------------------------------------
  def valid_parent
    validate_associated_user(:parent)
    # Immutable ancestry prevents concurrent reparenting from introducing cycles.
    if persisted? && (will_save_change_to_parent_id? || will_save_change_to_user_id?)
      errors.add(:parent, "and owner cannot change after creation")
    end
    errors.add(:parent, "cannot be itself") if parent && (parent == self || parent_id == id)
  end
end
