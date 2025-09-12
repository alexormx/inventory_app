// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
// Deshabilitar acciones críticas (Payments/Shipments) hasta que cargue por completo
import "custom/defer_actions_until_loaded"
import { Application } from "@hotwired/stimulus"
// Cargar inmediatamente el módulo de líneas de ajustes para asegurar funcionalidad en formularios
import "components/inventory_adjustment_lines"

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
import ConfirmController from "./controllers/confirm_controller"
application.register("confirm", ConfirmController)
// Gallery controller cargado de forma tolerante para evitar bloquear el bundle si falta default
import("./controllers/gallery_controller").then(mod => {
  const Ctl = mod.default || mod.GalleryController;
  if (Ctl) {
    application.register("gallery", Ctl);
  } else {
    console.warn("[gallery_controller] módulo sin export compatible (default/GalleryController)");
  }
}).catch(err => {
  console.warn("[gallery_controller] carga diferida falló", err);
});
import("./controllers/simple_tabs_controller").then(mod => {
  const Ctl = mod.default || mod.SimpleTabsController;
  if(Ctl){ application.register("simple-tabs", Ctl); }
  else { console.warn("[simple_tabs_controller] módulo sin export válido"); }
}).catch(err => console.warn("[simple_tabs_controller] carga diferida falló", err));
import("./controllers/simple_accordion_controller").then(mod => {
  const Ctl = mod.default || mod.SimpleAccordionController;
  if(Ctl){
    application.register("simple-accordion", Ctl)
  } else {
    console.warn("[simple_accordion_controller] módulo sin export válido");
  }
}).catch(err => console.warn("[simple_accordion_controller] carga diferida falló", err));

// Remove Stimulus dropdown controller (using vanilla JS now)
// import DropdownController from "./controllers/dropdown_controller"
// application.register("dropdown", DropdownController)
// console.debug("DropdownController registered")
// --- Lazy hydration: módulos no críticos diferidos ---
// Criterio: dejar sólo lo imprescindible para interacción inmediata (Turbo + Stimulus controllers ya registrados).
// El resto (UI decorativa, overlays, tooltips, efectos de scroll, formularios avanzados) se carga cuando el navegador está ocioso.

const lazyModules = [
  () => import("custom/dropdown_toggle"),
  () => import("custom/menu"),
  () => import("custom/toggle_inventory_items"),
  () => import("custom/payment_modal"),
  () => import("custom/hide_modal"),
  () => import("custom/cookies"),
  () => import("custom/navbar_shrink"),
  () => import("custom/search_overlay"),
  () => import("custom/theme_toggle"),
  () => import("custom/cart_preview"),
  () => import("custom/cart_preview_dynamic"),
  () => import("custom/flash_stack_offset"),
  () => import("custom/tooltip_init"),
  () => import("modules/toggle_menu"),
  () => import("modules/flash_messages"),
  () => import("modules/disable_enter_until_email"),
  () => import("modules/sidebar_toggle"),
  () => import("components/password_validation"),
  () => import("components/show_password_requirements"),
  () => import("components/total_cost_calculation"),
  () => import("components/order_items")
];

function hydrateLazy(){
  // Importar en cadena para no saturar el main thread; se pueden paralelizar si se prefiere.
  lazyModules.reduce((p, loader)=> p.then(()=> loader().catch(()=>{})), Promise.resolve());
}

// Estrategia: usar requestIdleCallback con timeout; fallback a evento load.
if('requestIdleCallback' in window){
  requestIdleCallback(()=>hydrateLazy(), { timeout: 3000 });
} else {
  window.addEventListener('load', hydrateLazy);
}
// Dashboard controllers
import ChartController from "./controllers/chart_controller"
application.register("chart", ChartController)

// Ensure charts helpers are importable (side-effect import ok)
import "./dashboard/charts"

// Marcar el estado de carga para estilos CSS: bloquear botones críticos hasta estar listo
document.addEventListener('turbo:before-render', () => {
  document.body && document.body.classList.remove('app-ready')
})
document.addEventListener('turbo:load', () => {
  document.body && document.body.classList.add('app-ready')
})

