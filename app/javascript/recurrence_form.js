// app/javascript/recurrence_form.js
(function () {
  function el(id) { return document.getElementById(id); }

  function updateVisibility() {
    const kind   = document.getElementById("item_recurrence_kind");
    const unit   = document.getElementById("item_recurrence_unit");
    const domBox = el("field_dom");
    const moyBox = el("field_moy");

    if (!kind || !unit || !domBox || !moyBox) return;

    const u = unit.value; // "day" | "week" | "month" | "year"

    // Show DOM for month/year; show MOY only for year
    const isRecurring = kind.value !== "no_recurrence";
    const showDom = isRecurring && (u === "month" || u === "year");
    const showMoy = isRecurring && (u === "year");

    domBox.style.display = showDom ? "" : "none";
    moyBox.style.display = showMoy ? "" : "none";

    // Disable inputs when hidden (so params don’t carry stale values)
    const domInput = document.getElementById("item_recurrence_day_of_month");
    const moyInput = document.getElementById("item_recurrence_month_of_year");
    if (domInput) domInput.disabled = !showDom;
    if (moyInput) moyInput.disabled = !showMoy;
  }

  function setup() {
    const k = document.getElementById("item_recurrence_kind");
    const u = document.getElementById("item_recurrence_unit");
    if (!k || !u) return;

    const recurrenceFields = ["item_recurrence_interval"];
    const toggleAll = () => {
      const isNone = k.value === "no_recurrence";
      u.disabled = isNone;
      recurrenceFields.forEach(id => {
        const input = document.getElementById(id);
        if (input) input.disabled = isNone;
      });
    };

    k.addEventListener("change", () => { toggleAll(); updateVisibility(); });
    u.addEventListener("change", updateVisibility);

    toggleAll();
    updateVisibility();
  }

  document.addEventListener("turbo:load", setup);
  document.addEventListener("turbo:frame-load", setup);
  document.addEventListener("DOMContentLoaded", setup);
})();
