// Customer Stimulus registry: only controllers used on public/customer-facing
// pages. Admin-only controllers (audit-progress, dropzone, kv-editor, tabs,
// toggle-inventory, product-search, user-suggest, inventory-locations,
// location-suggest, bulk-location-assign, inventory-transfer,
// catalog-item-search, catalog-review, editor-mode) are registered only in the
// admin bundle (controllers/index.js) to keep them off public pages.
import { Application } from "@hotwired/stimulus"
const application = Application.start()

import CartItemController from "./cart_item_controller"
import ClearSearchController from "./clear_search_controller"
import ConfirmController from "./confirm_controller"
import CookiesController from "./cookies_controller"
import DropdownController from "./dropdown_controller"
import GalleryController from "./gallery_controller"
import HideModalController from "./hide_modal_controller"
import ModalController from "./modal_controller"
import NavbarController from "./navbar_controller"
import PaymentModalController from "./payment_modal_controller"
import PollingFrameController from "./polling_frame_controller"
import ProductFormController from "./product_form_controller"
import ProductMetaController from "./product_meta_controller"
import ShipmentGuardController from "./shipment_guard_controller"
import SimpleAccordionController from "./simple_accordion_controller"
import SimpleTabsController from "./simple_tabs_controller"
import SubtabsController from "./subtabs_controller"
import CatalogFiltersController from "./catalog_filters_controller"
import PriceRangeController from "./price_range_controller"
import CollectibleQuickAddController from "./collectible_quick_add_controller"
import CatalogLinkController from "./catalog_link_controller"
import FilterListController from "./filter_list_controller"
import BackToTopController from "./back_to_top_controller"
import RecentlyViewedController from "./recently_viewed_controller"
import PostTocController from "./post_toc_controller"
import CopyController from "./copy_controller"

application.register("cart-item", CartItemController)
application.register("clear-search", ClearSearchController)
application.register("confirm", ConfirmController)
application.register("cookies", CookiesController)
application.register("dropdown", DropdownController)
application.register("gallery", GalleryController)
application.register("hide-modal", HideModalController)
application.register("modal", ModalController)
application.register("navbar", NavbarController)
application.register("payment-modal", PaymentModalController)
application.register("polling-frame", PollingFrameController)
application.register("product-form", ProductFormController)
application.register("product-meta", ProductMetaController)
application.register("shipment-guard", ShipmentGuardController)
application.register("simple-accordion", SimpleAccordionController)
application.register("simple-tabs", SimpleTabsController)
application.register("subtabs", SubtabsController)
application.register("catalog-filters", CatalogFiltersController)
application.register("price-range", PriceRangeController)
application.register("collectible-quick-add", CollectibleQuickAddController)
application.register("catalog-link", CatalogLinkController)
application.register("filter-list", FilterListController)
application.register("back-to-top", BackToTopController)
application.register("recently-viewed", RecentlyViewedController)
application.register("post-toc", PostTocController)
application.register("copy", CopyController)

window.Stimulus = application
