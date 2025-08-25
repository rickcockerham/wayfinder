# app/services/recurrence_generator.rb
class RecurrenceGenerator
  def initialize(item)
    @item = item
  end

  def call
    return unless @item.recurrence_kind.present? && !@item.recurrence_none?

    next_deadline =
      if @item.fixed_schedule?
        @item.next_deadline_from_schedule
      else
        @item.next_deadline_from_completion
      end
    return unless next_deadline

    dup = @item.dup
    dup.done = false
    dup.completed_at = nil
    dup.deadline = next_deadline
    # Keep the anchor start date for fixed schedule; for after_completion we can keep the original too
    dup.recurrence_start_on ||= @item.recurrence_start_on

    dup.save!

    # Optional: copy materials requirements
    @item.material_requirements.find_each do |mr|
      dup.material_requirements.create!(name: mr.name, qty_needed: mr.qty_needed, unit: mr.unit, shop_id: mr.shop_id)
    end

    dup
  end
end
