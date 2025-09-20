import "@hotwired/turbo-rails"
import "./controllers"   // index.js arranca Stimulus y registra todo

// Legacy helpers still in vanilla
import "./custom/cart_preview"
import "./custom/cart_preview_dynamic"
// Abre el <dialog> cuando se carga el frame del modal de pagos
import "./custom/payment_modal"

// Órdenes: cálculo de costos y totales (SO/PO)
import "./components/order_items"
import "./components/purchase_order_items"

// Navbar: comportamiento de reducción de altura al hacer scroll
import "./custom/navbar_shrink"
// Navbar: hamburguesa/collapse sin Bootstrap JS
import "./custom/navbar_toggle"
// Tema claro/oscuro (persistencia en localStorage)
import "./custom/theme_toggle"
// Tooltips (si hay data-bs-toggle="tooltip")
import "./custom/tooltip_init"
// Admin: ajustes de inventario (form dinámico)
import "./components/inventory_adjustment_lines"

// Devise: validación y requisitos de contraseña
import "./components/password_validation"
import "./components/show_password_requirements"

// Production: disable verbose debug
window.APP_DEBUG = false

