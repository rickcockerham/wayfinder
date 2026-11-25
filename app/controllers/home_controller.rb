# coding: utf-8
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  include FilterPersistence

  before_action :load_lookups

  #-----------------------------------------------------------------------------
  def index
    # --- read params / defaults via persistence ---
    f = current_filters
    @selected_mood_ids    = f[:mood_ids]
    @selected_category_id = f[:category_id]
    @time_i               = f[:time_i]
    @query                = f[:q]
    @sort                 = f[:sort]
    @per                  = f[:per]
    @filters = f

    # Use the same selection as the read-only priorities API.
    @items = HomeItemSelection.new(current_user, f).call

    @top_items = @items.first(@per)

    # --- per-item missing list for the table ---
    inv = InventoryItem.for_user(current_user).group_by { |i| i.name.downcase }
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

  #-----------------------------------------------------------------------------
  def load_lookups
    @moods      = Mood.for_user(current_user).visible.order(:name).to_a
    @categories = Category.for_user(current_user).visible.order(:name).to_a
    @shops      = Shop.for_user(current_user).visible.order(:name).to_a
  end


  # Aggregate shortages across the CURRENT top items for one vendor.
  #-----------------------------------------------------------------------------
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
      inventory = Array.wrap(inventory_hash[row[:name].downcase]).select { |stock| stock.unit.to_s == row[:unit] }
      if inventory.any? { |stock| stock.qty_have.nil? }
        next { name: row[:name], short: nil, unit: row[:unit], quantity_unknown: true }
      end
      have = inventory.sum { |stock| stock.qty_have.to_f }
      short = row[:needed] - have
      short > 0 ? { name: row[:name], short: short, unit: row[:unit] } : nil
    end.sort_by { |h| h[:name] }
  end
end
