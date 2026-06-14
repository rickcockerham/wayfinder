class NormalizeLegacyTimeScales < ActiveRecord::Migration[7.1]
  class MigrationItem < ApplicationRecord
    self.table_name = "items"
  end

  def up
    MigrationItem.reset_column_information

    MigrationItem.find_each do |item|
      normalized = normalized_time_scale(item.time_scale)
      next if normalized == item.time_scale

      item.update_columns(time_scale: normalized)
    end
  end

  def down; end

  private

  def normalized_time_scale(value)
    level = value.to_i
    return level if (0..7).cover?(level)
    return 0 if level <= 30
    return 1 if level <= 60
    return 2 if level <= 8 * 60
    return 3 if level <= 24 * 60
    return 4 if level <= 7 * 24 * 60
    return 5 if level <= 30 * 24 * 60
    return 6 if level <= 365 * 24 * 60

    7
  end
end
