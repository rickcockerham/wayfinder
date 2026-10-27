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
  #   deficits: shortage amounts, or quantity_unknown with nil shortage for uncounted stock
  # -----------------------------------------------------------------------------
  def consume!
    res = Result.new(0, [])

    ActiveRecord::Base.transaction do
      # lock inventory rows we’re going to touch
      @item.item_inventories.for_user(@item.user).includes(:inventory_item).find_each do |ii|
        next unless ii.qty_reserved.to_f.positive?
        inv = ii.inventory_item.lock!  # SELECT ... FOR UPDATE

        consume = ii.qty_reserved.to_f
        # Consumption from an unknown starting count cannot establish a numeric balance.
        if inv.qty_have.nil?
          res.deficits << { name: inv.name, shortage: nil, quantity_unknown: true }
        else
          new_qty = inv.qty_have.to_f - consume
          if new_qty.negative?
            res.deficits << { name: inv.name, shortage: new_qty.abs }
            new_qty = 0.0
          end
          inv.update!(qty_have: new_qty)
        end
        ii.update!(qty_reserved: 0)

        # optional tidy-up: remove empty reservation rows
        ii.destroy if ii.qty_reserved.to_f.zero?
        res.consumed_lines += 1
      end
    end

    res
  end
end
