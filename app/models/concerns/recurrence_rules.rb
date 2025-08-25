# app/models/concerns/recurrence_rules.rb
module RecurrenceRules
  module_function

  def next_occurrence(unit:, interval:, base_date:, day_of_month: nil, month_of_year: nil)
    interval = interval.to_i.clamp(1, 10_000)
    case unit
    when :day   then base_date + interval
    when :week  then base_date + 7 * interval
    when :month
      if day_of_month
        add_months_clamped(base_date, interval, day_of_month)
      else
        add_months_clamped(base_date, interval, base_date.day)
      end
    when :year
      if month_of_year && day_of_month
        next_year_fixed_date(base_date, interval, month_of_year, day_of_month)
      else
        # yearly by “same month/day” from base
        next_year_fixed_date(base_date, interval, base_date.month, base_date.day)
      end
    else
      nil
    end
  end

  def add_months_clamped(date, months, target_dom)
    y = date.year
    m = date.month + months
    y += (m - 1) / 12
    m = ((m - 1) % 12) + 1
    last_dom = Date.civil(y, m, -1).day
    dom = [target_dom, last_dom].min
    Date.new(y, m, dom)
  end

  def next_year_fixed_date(base, interval, month, dom)
    year = base.year
    candidate = safe_date(year, month, dom)
    if candidate <= base
      year += interval
      candidate = safe_date(year, month, dom)
    end
    candidate
  end

  def safe_date(y, m, d)
    last = Date.civil(y, m, -1).day
    Date.new(y, m, [d, last].min)
  end
end
