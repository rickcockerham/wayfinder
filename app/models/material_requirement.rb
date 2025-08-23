
# app/models/material_requirement.rb
class MaterialRequirement < ApplicationRecord
  belongs_to :item
  belongs_to :shop, optional: true
  validates :name, presence: true
end
