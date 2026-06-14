
# app/models/mood.rb
class Mood < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :restrict_with_exception
  scope :visible, -> { where(hidden: false) }
  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
end
