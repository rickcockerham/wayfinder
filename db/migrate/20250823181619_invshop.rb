class Invshop < ActiveRecord::Migration[7.1]
  def change
    add_reference :inventory_items, :shop, foreign_key: true, null: true
  end
end
