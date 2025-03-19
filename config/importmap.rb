# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/custom",      under: "custom"
pin_all_from "app/javascript/modules",     under: "modules"
pin_all_from "app/javascript/components",  under: "components"
pin_all_from "app/javascript/utilities",   under: "utilities"
