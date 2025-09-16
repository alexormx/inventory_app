import "@hotwired/turbo-rails"
import "./controllers"   // index.js arranca Stimulus y registra todo

// --- Legacy vanilla helpers (aún no migrados a Stimulus) ---
// Dropdown toggles based on data-dropdown-* attributes
// (Migrated dropdowns to Stimulus: legacy script removed)
// Cart preview hover/focus panel logic
import "./custom/cart_preview"

// (Opcional: inicializaciones globales no atadas a Stimulus)
window.APP_DEBUG = false
