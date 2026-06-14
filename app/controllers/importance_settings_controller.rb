class ImportanceSettingsController < ApplicationController
  before_action :set_importance_setting

  def show; end

  def update
    if @importance_setting.update(normalized_importance_setting_params)
      redirect_to importance_setting_path, notice: "Importance settings updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_importance_setting
    @importance_setting = current_user.importance_setting || current_user.create_importance_setting!(ImportanceSetting.default_attributes)
  end

  def importance_setting_params
    params.require(:importance_setting).permit(
      :personal_weight, :emotional_weight, :family_weight,
      :horizon_days, :urgency_weight, :overdue_cap_days, :overdue_per_day,
      :time_penalty_per_level, :time_penalty_max_level,
      :quick_task_max_level, :quick_task_bonus,
      :planner_morning_start_time, :planner_afternoon_start_time, :planner_evening_start_time,
      :timezone
    )
  end

  def normalized_importance_setting_params
    attrs = importance_setting_params.to_h
    attrs["planner_morning_start_minute"] = time_string_to_minutes(attrs.delete("planner_morning_start_time"))
    attrs["planner_afternoon_start_minute"] = time_string_to_minutes(attrs.delete("planner_afternoon_start_time"))
    attrs["planner_evening_start_minute"] = time_string_to_minutes(attrs.delete("planner_evening_start_time"))
    attrs
  end

  def time_string_to_minutes(value)
    hours, minutes = value.to_s.split(":").map(&:to_i)
    (hours * 60) + minutes
  end
end
