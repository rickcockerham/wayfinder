// app/javascript/filters_toggle.js
(function () {
  function setup() {
    const btn   = document.getElementById("toggle-filters");
    const panel = document.getElementById("filters-panel");
    if (!btn || !panel) return;

    const KEY = "home-filters-open";

    function setOpen(open) {
      panel.hidden = !open;                             // true => hide
      btn.setAttribute("aria-expanded", String(open));  // reflect current state
      btn.textContent = open ? "Filters ▴" : "Filters ▾";
      try { sessionStorage.setItem(KEY, String(open)); } catch(_) {}
    }

    // initial (default hidden)
    const saved = sessionStorage.getItem(KEY);
    setOpen(saved === "true");

    // avoid double binding across Turbo visits
    if (!btn.__bound) {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        setOpen(panel.hidden); // if hidden, we’re opening; if shown, we’re closing
      });
      btn.__bound = true;
    }
  }

  document.addEventListener("turbo:load", setup);
  document.addEventListener("turbo:frame-load", setup);
  document.addEventListener("DOMContentLoaded", setup);

  // keep DOM light when Turbo caches
  document.addEventListener("turbo:before-cache", () => {
    const panel = document.getElementById("filters-panel");
    if (panel && panel.hidden === false) {
      // leave as-is so it restores open state visually
    }
  });
})();
