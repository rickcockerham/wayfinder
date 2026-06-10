class RemoveRecurrenceStartOnFromItems < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:items, :recurrence_start_on)

    execute <<~SQL.squish
      UPDATE items
      SET deadline = recurrence_start_on
      WHERE deadline IS NULL AND recurrence_start_on IS NOT NULL
    SQL

    remove_column :items, :recurrence_start_on
  end

  def down
    return if column_exists?(:items, :recurrence_start_on)

    add_column :items, :recurrence_start_on, :date

    execute <<~SQL.squish
      UPDATE items
      SET recurrence_start_on = deadline
      WHERE recurrence_kind <> 0 AND deadline IS NOT NULL
    SQL
  end
end
