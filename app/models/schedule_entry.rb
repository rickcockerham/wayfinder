# app/models/schedule_entry.rb
class ScheduleEntry < ApplicationRecord
  enum day_part: { morning: 0, afternoon: 1, evening: 2 }

  belongs_to :category

  validates :on_date, presence: true
  validates :day_part, presence: true
  validates :category_id, presence: true
  validates :category_id, uniqueness: { scope: [:on_date, :day_part] }
end
