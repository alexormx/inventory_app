// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

const application = Application.start()
window.Stimulus = application

// Nota: Evitamos Bootstrap JS para tabs; usamos Stimulus nativo

import * as controllers from "./controllers"
for (const name in controllers) {
  application.register(name, controllers[name])
}

import CartItemController from "./controllers/cart_item_controller"
application.register("cart-item", CartItemController)

import KvEditorController from "./controllers/kv_editor_controller"
application.register("kv-editor", KvEditorController)

import DropzoneController from "./controllers/dropzone_controller"
application.register("dropzone", DropzoneController)

import TabsController from "./controllers/tabs_controller"
application.register("tabs", TabsController)

import SubtabsController from "./controllers/subtabs_controller"
application.register("subtabs", SubtabsController)

// Remove Stimulus dropdown controller (using vanilla JS now)
// import DropdownController from "./controllers/dropdown_controller"
// application.register("dropdown", DropdownController)
// console.debug("DropdownController registered")
import "custom/dropdown_toggle"

import "custom/menu"
import "custom/toggle_inventory_items"
import "custom/payment_modal"
import "custom/hide_modal"
import "custom/cookies"
import "custom/gallery"
import "custom/navbar_shrink"
import "custom/search_overlay"
import "custom/theme_toggle"
import "custom/cart_preview"
import "custom/flash_stack_offset"
import "modules/toggle_menu"
import "modules/flash_messages"
import "modules/disable_enter_until_email"
import "modules/sidebar_toggle"
import "components/password_validation"
import "components/show_password_requirements"
import "components/total_cost_calculation"
import "components/order_items"
// Dashboard controllers
import ChartController from "./controllers/chart_controller"
application.register("chart", ChartController)

// Ensure charts helpers are importable (side-effect import ok)
import "./dashboard/charts"

