# app/controllers/schedule_entries_controller.rb
class ScheduleEntriesController < ApplicationController
  # basic cookie auth you added still applies via ApplicationController
  before_action :set_week

  def index
    @categories = Category.order(:name).to_a
    @entries    = ScheduleEntry.where(on_date: @week).includes(:category).to_a
    @by_slot    = @entries.group_by { |e| [e.on_date, e.day_part] }
  end

  def create
    on_date   = Date.parse(params[:on_date])
    day_part  = params[:day_part].to_s
    category  = Category.find(params[:category_id])

    entry = ScheduleEntry.find_or_initialize_by(on_date:, day_part:, category:)
    entry.save!

    render_slot(on_date, day_part)
  rescue => e
    render turbo_stream: turbo_stream.replace(slot_dom_id(on_date, day_part),
      partial: "schedule_entries/slot",
      locals: { on_date:, day_part:, entries: [], error: e.message })
  end

  def destroy
    entry = ScheduleEntry.find(params[:id])
    on_date  = entry.on_date
    day_part = entry.day_part
    entry.destroy

    render_slot(on_date, day_part)
  end

  # DELETE /schedule_entries/clear?on_date=YYYY-MM-DD&day_part=morning
  def clear
    on_date  = Date.parse(params[:on_date])
    day_part = params[:day_part].to_s

    ScheduleEntry.where(on_date:, day_part:).delete_all
    render_slot(on_date, day_part)
  end

  private

  def set_week
    start = (params[:start].presence && Date.parse(params[:start])) || Date.current
    @week = (0..6).map { |i| start + i }
  end

  def render_slot(on_date, day_part)
    entries = ScheduleEntry.where(on_date:, day_part:).includes(:category).order("categories.name")
    render turbo_stream: turbo_stream.replace(
      slot_dom_id(on_date, day_part),
      partial: "schedule_entries/slot",
      locals: { on_date:, day_part:, entries:, error: nil }
    )
  end

  def slot_dom_id(date, part)
    "slot-#{date.strftime('%Y%m%d')}-#{part}"
  end
end
