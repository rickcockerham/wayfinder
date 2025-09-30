// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "wysiwyg"
import "filters_toggle"
import "recurrence_form"
import "planner_dnd"
import "buttonfidget"



(function () {
  function attach() {
    document.addEventListener("click", (e) => {
      const btn = e.target.closest('button[type="submit"], input[type="submit"]');
      if (!btn) return;
      btn.classList.add("ping");
      console.log("submit");
      // remove after a beat in case there's no redirect
      setTimeout(() => btn.classList.remove("ping"), 700);
    }, { capture: true });
  }
  document.addEventListener("turbo:load", attach);
  document.addEventListener("DOMContentLoaded", attach);
})();
