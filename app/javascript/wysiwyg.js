// app/javascript/wysiwyg.js
function initNotesEditor() {
  const input = document.getElementById("item_notes");
  const mount = document.getElementById("notes_editor");
  if (!input || !mount || typeof Quill === "undefined") return;

  // Avoid double-initializing when Turbo re-renders
  if (mount.__quill) return;

  const quill = new Quill(mount, {
    theme: "snow",
    modules: {
      toolbar: [
        [{ header: [2, 3, false] }],
        ["bold", "italic", "underline"],
        [{ list: "ordered" }, { list: "bullet" }],
        ["link", "code-block"],
        ["clean"],
      ],
    },
  });
  mount.__quill = quill;

  // Seed from hidden field
  if (input.value) quill.root.innerHTML = input.value;

  // Keep hidden field updated on submit
  const form = input.closest("form");
  if (form) {
    form.addEventListener("submit", () => {
      input.value = quill.root.innerHTML;
    });
  }
}

// Re-init on every Turbo visit or frame load (and initial DOM load)
document.addEventListener("turbo:load", initNotesEditor);
document.addEventListener("turbo:frame-load", initNotesEditor);
document.addEventListener("DOMContentLoaded", initNotesEditor);

// Before Turbo caches the page, tear down Quill and persist HTML
document.addEventListener("turbo:before-cache", () => {
  const input = document.getElementById("item_notes");
  const mount = document.getElementById("notes_editor");
  if (mount && mount.__quill) {
    if (input) input.value = mount.__quill.root.innerHTML;
    // “Destroy” the instance so we don’t duplicate toolbars on restore
    mount.__quill.disable();
    mount.__quill = null;
    // Replace editor DOM with static HTML so the cached page is lightweight
    mount.classList.remove("ql-container", "ql-snow");
    mount.innerHTML = input ? input.value : mount.innerHTML;
  }
});
