// app/javascript/planner_dnd.js
(function () {
  let pickerSlot = null;

  function coarsePointer() {
    return window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
  }

  function assignCategoryToSlot(slot, catId) {
    if (!catId) return;

    const form = slot.querySelector("form.add-entry-form");
    if (!form) return;

    const input = form.querySelector(".cat-id-input");
    input.value = catId;
    form.requestSubmit();
  }

  function setupPicker() {
    const picker = document.getElementById("planner-category-picker");
    if (!picker) return;

    picker.querySelectorAll(".planner-picker-option").forEach(button => {
      button.addEventListener("click", () => {
        if (!pickerSlot) return;

        assignCategoryToSlot(pickerSlot, button.dataset.catId);
        picker.close();
        pickerSlot = null;
      });
    });

    picker.addEventListener("close", () => {
      pickerSlot = null;
    });
  }

  function onLoad() {
    // Make category chips draggable with their id
    document.querySelectorAll(".cat-chip[draggable=true]").forEach(chip => {
      chip.addEventListener("dragstart", (e) => {
        e.dataTransfer.setData("text/plain", chip.dataset.catId);
      });
    });

    document.querySelectorAll(".slot").forEach(slot => {
      slot.addEventListener("dragover", (e) => e.preventDefault());
      slot.addEventListener("drop", (e) => {
        e.preventDefault();
        assignCategoryToSlot(slot, e.dataTransfer.getData("text/plain"));
      });

      slot.addEventListener("click", () => {
        if (!coarsePointer()) return;

        const picker = document.getElementById("planner-category-picker");
        if (!picker) return;

        pickerSlot = slot;
        picker.showModal();
      });
    });
    setupPicker();
  }

  document.addEventListener("turbo:load", onLoad);
  document.addEventListener("turbo:frame-load", onLoad);
  document.addEventListener("DOMContentLoaded", onLoad);
})();
