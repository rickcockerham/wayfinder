// app/javascript/planner_dnd.js
(function () {
  function onLoad() {
    // Make category chips draggable with their id
    document.querySelectorAll(".cat-chip[draggable=true]").forEach(chip => {
      chip.addEventListener("dragstart", (e) => {
        e.dataTransfer.setData("text/plain", chip.dataset.catId);
      });
    });

    // Each slot’s drop zone is the .slot-chips div (handlers bound inline via data-action too)
    document.querySelectorAll(".slot").forEach(slot => {
      slot.addEventListener("dragover", (e) => e.preventDefault());
      slot.addEventListener("drop", (e) => {
        e.preventDefault();
        const catId = e.dataTransfer.getData("text/plain");
        if (!catId) return;

        const form = slot.querySelector("form.add-entry-form");
        const input = form.querySelector(".cat-id-input");
        input.value = catId;
        // Turbo will swap the slot frame with server response
        form.requestSubmit();
      });
    });
  }

  document.addEventListener("turbo:load", onLoad);
  document.addEventListener("turbo:frame-load", onLoad);
  document.addEventListener("DOMContentLoaded", onLoad);
})();
