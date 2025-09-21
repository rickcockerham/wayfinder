# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "filters_toggle", to: "filters_toggle.js"
pin "wysiwyg", to: "wysiwyg.js"
pin "recurrence_form", to: "recurrence_form.js"
pin "planner_dnd", to: "planner_dnd.js"
