// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

const application = Application.start()

import * as controllers from "./controllers"
for (const name in controllers) {
  application.register(name, controllers[name])
}
