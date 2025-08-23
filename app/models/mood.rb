
# app/models/mood.rb
class Mood < ApplicationRecord
  has_many :items, dependent: :restrict_with_exception
  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
