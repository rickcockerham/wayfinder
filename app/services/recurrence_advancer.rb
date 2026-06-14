class RecurrenceAdvancer
  def initialize(item)
    @item = item
  end

  def call
    return unless @item.recurrence_kind.present? && !@item.no_recurrence?

    next_deadline =
      if @item.fixed_schedule?
        @item.next_deadline_from_schedule
      else
        @item.next_deadline_from_completion
      end
    return unless next_deadline

    @item.update!(
      deadline: next_deadline,
      done: false,
      completed_at: nil
    )

    @item
  end
end
