import "@hotwired/turbo-rails"
import "./controllers"   // index.js arranca Stimulus y registra todo

// Legacy helpers still in vanilla
import "./custom/cart_preview"

// Production: disable verbose debug
window.APP_DEBUG = false

