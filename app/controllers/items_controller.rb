# app/controllers/items_controller.rb
class ItemsController < ApplicationController
  before_action :set_item, only: %i[show edit update destroy materials materials_post]

  def index
    base = Item.includes(:category, :mood, :parent, :blockers, :blocks).order_by_importance
    if !params[:dones]
      base = base.where(done: false)
    end
     items = base.limit(200).to_a
    @items = DependencyList.new(items).call
  end

  def show
    @blocking_edges = ItemBlock.where(blocked_id: @item.id).includes(:blocker)
    @blocks_out = ItemBlock.where(blocker_id: @item.id).includes(:blocked)
  end

  def new
    @item = Item.new
    @item.parent_id ||= params[:parent_id]
  end

  def edit; end

  def create
    @item = Item.new(item_params)
    if @item.save
      redirect_to items_path, notice: "Item was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @item.update(item_params)
      if @item.saved_change_to_done? && @item.done?
        result = ItemCompletion.new(@item).consume!
        msg = "Item completed. Consumed #{result.consumed_lines} material line#{'s' if result.consumed_lines != 1}."
        if result.deficits.any?
          missing = result.deficits.map { |d| "#{d[:name]} (short #{d[:shortage]})" }.join(", ")
          msg << " Inventory short on: #{missing}."
        end
        redirect_to root_path, notice: msg and return
      end
      redirect_to @item, notice: "Item updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy
    redirect_to items_url, notice: "Item was successfully destroyed."
  end

  def materials
    @q     = params[:q].to_s.strip
    @page  = [params[:page].to_i, 1].max
    @per   = 25

    scope = InventoryItem.order(:name)
    scope = scope.where("LOWER(name) LIKE ?", "%#{@q.downcase}%") if @q.present?

    @total = scope.count
    @pages = (@total.to_f / @per).ceil
    @inventory_page = scope.offset((@page - 1) * @per).limit(@per).to_a

    @req_by_downcase = @item.material_requirements.index_by { |mr| mr.name.downcase }

    @shops   = Shop.order(:name).to_a
    @shop_id = params[:shop_id].presence&.to_i
  end

  def materials_post
    @shop_id = params[:shop_id].presence&.to_i
    shop     = @shop_id ? Shop.find_by(id: @shop_id) : nil
    created_or_updated = 0

    # From table rows (InventoryItem catalog)
    (params[:quantities] || {}).each do |inv_id, qty|
      qty_i = qty.to_i
      next if qty_i <= 0
      inv = InventoryItem.find_by(id: inv_id)
      next unless inv
      effective_shop = shop || inv.shop
      upsert_requirement!(@item, inv.name, qty_i, inv.unit, effective_shop)
      created_or_updated += 1
    end

    # From the 3 quick-add lines
    new_names = Array(params[:new_names])
    new_qtys  = Array(params[:new_qtys])
    new_shop_ids  = Array(params[:new_shop_ids])
    Array(params[:new_names]).zip(Array(params[:new_qtys]), Array(params[:new_shop_ids])).each do |name, qty, explicit_shop_id|
      name = name.to_s.strip
      qty_i = qty.to_i
      next if name.blank? || qty_i <= 0
      explicit_shop = explicit_shop_id.present? ? Shop.find_by(id: explicit_shop_id) : sho
      upsert_requirement!(@item, name, qty_i, "", shop)
      created_or_updated += 1
    end

    redirect_to materials_item_path(
      @item,
      q: params[:q], page: params[:page], shop_id: @shop_id
    ), notice: "#{created_or_updated} material#{'s' if created_or_updated != 1} added/updated."
  end

  private

  def upsert_requirement!(item, name, qty, unit, shop = nil)
    mr = item.material_requirements.where("LOWER(name)=?", name.downcase).first
    if mr
      attrs = { qty_needed: qty, unit: (unit.presence || mr.unit.to_s) }
      attrs[:shop] = shop if shop.present?           # only change vendor if selected
      mr.update!(attrs)
    else
      item.material_requirements.create!(
        name: name, qty_needed: qty, unit: unit.to_s, shop: shop
      )
    end
  end

  def set_item
    @item = Item.find(params[:id])
    @material_requirements = @item.material_requirements.includes(:shop) if @item
  end

  def item_params
    params.require(:item).permit(
      :title, :notes,
      :category_id, :mood_id, :parent_id,
      :personal_impact, :emotional_impact, :family_impact,
      :time_estimate_minutes, :cost_cents,
      :deadline, :done
    )
  end
end
