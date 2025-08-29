// Inicializa tooltips Bootstrap si la librería está disponible globalmente
document.addEventListener("turbo:load", () => {
  if (window.bootstrap && bootstrap.Tooltip) {
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      try { new bootstrap.Tooltip(el); } catch(e) { /* ignore */ }
    });
  }
});

// Fallback simple usando title nativo si no hay Bootstrap JS
document.addEventListener("turbo:load", () => {
  if (!(window.bootstrap && bootstrap.Tooltip)) {
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      // Browser default title already works; we could add a class if desired
    });
  }
});