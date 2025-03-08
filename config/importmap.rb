# Pin npm packages by running ./bin/importmap

pin "application"

# config/importmap.rb
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
