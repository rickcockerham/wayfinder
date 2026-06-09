# app/models/schedule_entry.rb
class ScheduleEntry < ApplicationRecord
  enum day_part: { morning: 0, afternoon: 1, evening: 2 }

  belongs_to :user
  belongs_to :category

  before_validation :inherit_user_from_category

  validates :on_date, presence: true
  validates :day_part, presence: true
  validates :category_id, presence: true
  validates :category_id, uniqueness: { scope: [:on_date, :day_part] }
  validate :category_belongs_to_user

  private

  def inherit_user_from_category
    self.user ||= category&.user
  end

  def category_belongs_to_user
    validate_associated_user(:category)
  end
end
