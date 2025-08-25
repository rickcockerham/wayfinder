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
    const showDom = (u === "month" || u === "year");
    const showMoy = (u === "year");

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

    // Default: if kind is "none", keep everything hidden except the core fields
    const coreFields = ["item_recurrence_unit","item_recurrence_interval","item_recurrence_start_on"];
    const toggleAll = () => {
      const isNone = k.value === "none";
      u.disabled = isNone;
      coreFields.slice(1).forEach(id => {
        const input = document.getElementById(id);
        if (input) input.disabled = isNone;
      });
      // also hide conditional areas when none
      const domBox = el("field_dom"), moyBox = el("field_moy");
      if (domBox) domBox.style.display = isNone ? "none" : domBox.style.display;
      if (moyBox) moyBox.style.display = isNone ? "none" : moyBox.style.display;
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
