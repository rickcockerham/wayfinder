# coding: utf-8
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  before_action :load_lookups

  MAX_MINUTES = 600
  PER_OPTIONS = [5, 10, 20, 30].freeze

  def index
    # --- read params / defaults ---
    @selected_mood_ids = (params[:mood_ids] || @moods.map(&:id)).map(&:to_i).uniq
    @selected_category_id = params[:category_id].presence&.to_i
    @minutes = (params[:minutes].presence || MAX_MINUTES).to_i.clamp(0, MAX_MINUTES)
    @sort = %w[time importance].include?(params[:sort]) ? params[:sort] : "importance"
    @per  = (params[:per].to_i if PER_OPTIONS.include?(params[:per].to_i)) || 5

    # --- base scope ---
    scope = Item.includes(:category, :mood, :material_requirements).where(done: false)
    scope = scope.where(mood_id: @selected_mood_ids) if @selected_mood_ids.any?
    scope = scope.where(category_id: @selected_category_id) if @selected_category_id.present?
    scope = scope.where("time_estimate_minutes <= ?", @minutes) if @minutes < MAX_MINUTES

    @items = if @sort == "time"
      scope.order(:time_estimate_minutes, deadline: :asc).to_a
    else
      scope.to_a.sort_by { |it| -it.importance_score }
    end

    @top_items = @items.first(@per)

    # --- per-item missing list for the table ---
    inv = InventoryItem.all.index_by { |i| i.name.downcase }
    @missing_by_item = {}
    @top_items.each { |it| @missing_by_item[it.id] = it.missing_materials_by(inv) }

    # --- shopping list (by vendor) for currently shown items ---
    @selected_shop_id = begin
      raw = params[:shop_id].presence || @shops.first&.id
      raw&.to_i
    end
    @shopping_list = build_shopping_list(@top_items, inv, @selected_shop_id) if @selected_shop_id.present?
  end

  private

  def load_lookups
    @moods      = Mood.order(:name).to_a
    @categories = Category.order(:name).to_a
    @shops      = Shop.order(:name).to_a
  end


  # Aggregate shortages across the CURRENT top items for one vendor.
  def build_shopping_list(items, inventory_hash, shop_id)
    need = Hash.new { |h, k| h[k] = { name: k[0], unit: k[1], needed: 0.0 } }

    items.each do |it|
      it.material_requirements.each do |mr|
        next unless mr.shop_id == shop_id
        key = [mr.name.downcase, mr.unit.to_s]
        need[key][:name]   = mr.name # keep original casing from first seen
        need[key][:unit]   = mr.unit.to_s
        need[key][:needed] += mr.qty_needed.to_f
      end
    end

    need.values.filter_map do |row|
      have = inventory_hash[row[:name].downcase]&.qty_have.to_f
      short = row[:needed] - have
      short > 0 ? { name: row[:name], short: short, unit: row[:unit] } : nil
    end.sort_by { |h| h[:name] }
  end
end
