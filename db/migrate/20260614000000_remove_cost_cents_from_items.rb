class RemoveCostCentsFromItems < ActiveRecord::Migration[7.1]
  def change
    remove_column :items, :cost_cents, :integer
  end
end
