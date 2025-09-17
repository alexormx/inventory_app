import "@hotwired/turbo-rails"
import "./controllers"   // index.js arranca Stimulus y registra todo

// Legacy helpers still in vanilla
import "./custom/cart_preview"

// Órdenes: cálculo de costos y totales (SO/PO)
import "./components/order_items"
import "./components/purchase_order_items"

// Navbar: comportamiento de reducción de altura al hacer scroll
import "./custom/navbar_shrink"

// Production: disable verbose debug
window.APP_DEBUG = false

