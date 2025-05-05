// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

const application = Application.start()


import * as controllers from "./controllers"
for (const name in controllers) {
  application.register(name, controllers[name])
}

import "custom/menu"
import "custom/toggle_inventory_items"
import "custom/payment_modal"
import "custom/hide_modal"
import "modules/toggle_menu"
import "modules/flash_messages"
import "modules/disable_enter_until_email"
import "modules/sidebar_toggle"
import "components/password_validation"
import "components/show_password_requirements"
import "components/total_cost_calculation"
import "components/order_items"

