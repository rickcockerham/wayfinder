class ItemBlock < ApplicationRecord
  belongs_to :user
  belongs_to :blocker, class_name: "Item"
  belongs_to :blocked, class_name: "Item"

  before_validation :inherit_user_from_items

  validates :blocker_id, :blocked_id, presence: true
  validates :blocked_id, uniqueness: { scope: :blocker_id } # no dup edges
  validate :items_belong_to_user
  validate :items_share_user
  validate :acyclic_dependency, if: -> { new_record? || will_save_change_to_blocker_id? || will_save_change_to_blocked_id? }

  private

  #-----------------------------------------------------------------------------
  def acyclic_dependency
    return if blocker_id.blank? || blocked_id.blank? || user_id.blank? || errors.any?
    if blocker_id == blocked_id
      errors.add(:blocked, "cannot be the blocker itself")
      return
    end
    # A -> B is invalid if following B's outgoing links can already reach A.
    # Walk iteratively and ignore this edge on edits; legacy cycles cannot loop forever.
    frontier = [blocked_id]
    visited = {}
    edges = self.class.for_user(user_id)
    edges = edges.where.not(id: id) if persisted?
    until frontier.empty?
      if frontier.include?(blocker_id)
        errors.add(:blocked, "would create a dependency cycle")
        return
      end
      frontier.each { |item_id| visited[item_id] = true }
      frontier = edges.where(blocker_id: frontier).distinct.pluck(:blocked_id).reject { |item_id| visited[item_id] }
    end
  end

  #-----------------------------------------------------------------------------
  def inherit_user_from_items
    self.user ||= blocker&.user || blocked&.user
  end

  #-----------------------------------------------------------------------------
  def items_belong_to_user
    validate_associated_user(:blocker)
    validate_associated_user(:blocked)
  end

  #-----------------------------------------------------------------------------
  def items_share_user
    return if blocker.blank? || blocked.blank?
    return if blocker.user_id == blocked.user_id

    errors.add(:blocked, "must belong to the same user as blocker")
  end
end
