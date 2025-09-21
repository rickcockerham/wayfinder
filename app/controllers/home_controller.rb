# coding: utf-8
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  include FilterPersistence

  before_action :load_lookups

  def index
    # --- read params / defaults via persistence ---
    f = current_filters
    @selected_mood_ids    = f[:mood_ids]
    @selected_category_id = f[:category_id]
    #@minutes              = f[:minutes]
    @time_i               = f[:time_i]
    @sort                 = f[:sort]
    @per                  = f[:per]
    @filters = f

    # --- base scope ---
    scope = Item
      .includes(:category, :mood, :material_requirements)
      .where(done: false)
      .where.missing(:blocking_edges)   # exclude blocked items

    scope = scope.where(mood_id: @selected_mood_ids) if @selected_mood_ids.any?
    scope = scope.where(category_id: @selected_category_id) if @selected_category_id.present?
    # Apply the time cap from index (0..7). 7 = Forever (no cap).
    scope = scope.where("time_estimate_minutes <= ?", @time_i) if @time_i < TIME_INDEX_LABELS.length - 1

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
      raw = params[:shop_id].presence || @shops.detect { |s| s.material_requirements.any? }&.id
      raw&.to_i
    end
    @shopping_list = build_shopping_list(@items, inv, @selected_shop_id) if @selected_shop_id.present?
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
