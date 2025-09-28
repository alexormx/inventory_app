import { Application } from "@hotwired/stimulus"
const application = Application.start()

// IMPORTS (uno por archivo controlador)
import AuditProgressController from "./audit_progress_controller"
import CartItemController from "./cart_item_controller"
import ChartController from "./chart_controller"
import ClearSearchController from "./clear_search_controller"
import ConfirmController from "./confirm_controller"
import CookiesController from "./cookies_controller"
import DropdownController from "./dropdown_controller"
import DropzoneController from "./dropzone_controller"
import GalleryController from "./gallery_controller"
import HideModalController from "./hide_modal_controller"
import KvEditorController from "./kv_editor_controller"
import ModalController from "./modal_controller"
import NavbarController from "./navbar_controller"
import PaymentModalController from "./payment_modal_controller"
import ProductMetaController from "./product_meta_controller"
import ShipmentGuardController from "./shipment_guard_controller"
import SimpleAccordionController from "./simple_accordion_controller"
import SimpleTabsController from "./simple_tabs_controller"
import SubtabsController from "./subtabs_controller"
import TabsController from "./tabs_controller"
import ToggleInventoryController from "./toggle_inventory_controller"
import ProductSearchController from "./product_search_controller"
import UserSuggestController from "./user_suggest_controller"

application.register("audit-progress", AuditProgressController)
application.register("cart-item", CartItemController)
application.register("chart", ChartController)
application.register("clear-search", ClearSearchController)
application.register("confirm", ConfirmController)
application.register("cookies", CookiesController)
application.register("dropdown", DropdownController)
application.register("dropzone", DropzoneController)
application.register("gallery", GalleryController)
application.register("hide-modal", HideModalController)
application.register("kv-editor", KvEditorController)
application.register("modal", ModalController)
application.register("navbar", NavbarController)
application.register("payment-modal", PaymentModalController)
application.register("product-meta", ProductMetaController)
application.register("shipment-guard", ShipmentGuardController)
application.register("simple-accordion", SimpleAccordionController)
application.register("simple-tabs", SimpleTabsController)
application.register("subtabs", SubtabsController)
application.register("tabs", TabsController)
application.register("toggle-inventory", ToggleInventoryController)
application.register("product-search", ProductSearchController)
application.register("user-suggest", UserSuggestController)

// Export opcional para debugging
window.Stimulus = application
try {
	const ids = Array.from(application.router.modules.map(m => m.identifier))
	console.debug('[stimulus] registered identifiers:', ids)
} catch(e) {
	console.debug('[stimulus] could not list identifiers', e)
}
