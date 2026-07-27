// Customer bundle: only controllers/modules used on public-facing pages.
// Admin-only code lives in admin.js (loaded by the admin layout) so it stays
// off public pages — keeps this bundle small for LCP/TBT.
import { Turbo } from "@hotwired/turbo-rails"
import "./controllers/customer"   // slimmed Stimulus registry
import { confirmDialog } from "./lib/confirm_dialog"

// Legacy helpers still in vanilla
import "./custom/cart_preview"
import "./custom/cart_preview_dynamic"
// Abre el <dialog> cuando se carga el frame del modal de pagos
import "./custom/payment_modal"

// Navbar: comportamiento de reducción de altura al hacer scroll
import "./custom/navbar_shrink"
// Navbar: hamburguesa/collapse sin Bootstrap JS
import "./custom/navbar_toggle"
// Flash messages: auto‑dismiss + close button
import "./modules/flash_messages"
// Customer layout: polyfills para collapse/offcanvas sin Bootstrap JS
import "./custom/bootstrap_polyfills"
// Tema claro/oscuro (persistencia en localStorage)
import "./custom/theme_toggle"
// Tooltips (si hay data-bs-toggle="tooltip")
import "./custom/tooltip_init"
// Consentimiento de cookies: muestra el banner y persiste la elección.
import "./custom/cookies"

// Devise: validación y requisitos de contraseña
import "./components/password_validation"
import "./components/show_password_requirements"

// Production: disable verbose debug
window.APP_DEBUG = false

Turbo.config.forms.confirm = (message, element, submitter) => {
	return confirmDialog(message, { element: submitter || element })
}

window.customConfirmDialog = confirmDialog
