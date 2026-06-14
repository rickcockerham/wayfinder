(function () {
  function attachMoodButtons() {
    document.querySelectorAll("[data-filter-chip]").forEach((button) => {
      if (button.dataset.filterChipBound === "true") return;
      button.dataset.filterChipBound = "true";

      button.addEventListener("click", () => {
        const inputId = button.dataset.filterTarget;
        const input = inputId ? document.getElementById(inputId) : null;
        if (!input) return;

        input.checked = !input.checked;
        button.classList.toggle("is-active", input.checked);
        button.setAttribute("aria-pressed", String(input.checked));
      });
    });
  }

  function attach() {
    const input = document.getElementById("time_i");
    const label = document.getElementById("time_i_label");
    attachMoodButtons();
    if (!input || !label) return;

    const labels = ["Quick", "Minutes", "Hours", "Days", "Weeks", "Months", "Years", "Forever"];
    const render = () => {
      label.textContent = labels[Number(input.value)] || "";
    };

    input.addEventListener("input", render);
    render();
  }

  document.addEventListener("turbo:load", attach);
  document.addEventListener("DOMContentLoaded", attach);
})();
