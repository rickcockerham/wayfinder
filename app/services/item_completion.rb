# coding: utf-8
# app/services/item_completion.rb
class ItemCompletion
  Result = Struct.new(:consumed_lines, :deficits)

  def initialize(item)
    @item = item
  end

  # Consumes reserved quantities from inventory when an item is completed.
  # Returns Result with:
  #   consumed_lines: count of ItemInventory lines processed
  #   deficits: [{ name:, shortage: Float }] when inventory didn’t have enough
  def consume!
    res = Result.new(0, [])

    ActiveRecord::Base.transaction do
      # lock inventory rows we’re going to touch
      @item.item_inventories.includes(:inventory_item).find_each do |ii|
        next unless ii.qty_reserved.to_f.positive?
        inv = ii.inventory_item.lock!  # SELECT ... FOR UPDATE

        consume = ii.qty_reserved.to_f
        new_qty = inv.qty_have.to_f - consume

        if new_qty.negative?
          res.deficits << { name: inv.name, shortage: new_qty.abs }
          new_qty = 0.0
        end

        inv.update!(qty_have: new_qty)
        ii.update!(qty_reserved: 0)

        # optional tidy-up: remove empty reservation rows
        ii.destroy if ii.qty_reserved.to_f.zero?
        res.consumed_lines += 1
      end
    end

    res
  end
end
