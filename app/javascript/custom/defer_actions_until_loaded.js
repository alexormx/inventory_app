// Deshabilita botones críticos hasta que la página esté cargada completamente
(function(){
  const selector = [
    // Payments
    'a[href*="/payments/new"]',
    'a[data-turbo-frame="modal_frame"]',
    'button[data-turbo-frame="modal_frame"]',
    // Shipments
    'a[href$="/shipments/new"]',
    'a[href*="/shipments/"][href$="/edit"]',
    'a[data-turbo-frame="shipment_modal"]',
    'button[data-turbo-frame="shipment_modal"]'
  ].join(',');

  let ready = false;

  // Bloquear clics a nivel documento hasta que la página esté lista
  function captureClick(e){
    if (ready) return;
    const target = e.target && e.target.closest ? e.target.closest(selector) : null;
    if (target) {
      e.preventDefault();
      e.stopImmediatePropagation();
      return false;
    }
  }

  document.addEventListener('click', captureClick, true);

  // Marcar/Desmarcar visualmente elementos coincidentes
  function setVisualDisabled(disabled){
    document.querySelectorAll(selector).forEach(el => {
      try {
        if (disabled) {
          el.classList.add('disabled');
          el.style.pointerEvents = 'none';
          el.style.opacity = '0.6';
          el.setAttribute('aria-disabled', 'true');
        } else {
          el.classList.remove('disabled');
          el.style.pointerEvents = '';
          el.style.opacity = '';
          el.removeAttribute('aria-disabled');
        }
      } catch(_) {}
    });
  }

  // Observar nuevas inserciones mientras no está listo
  const mo = new MutationObserver(() => { if (!ready) setVisualDisabled(true); });
  mo.observe(document.documentElement, { childList: true, subtree: true });

  function onReady(){
    ready = true;
    setVisualDisabled(false);
  }

  // Inicial: bloquear y deshabilitar visualmente
  setVisualDisabled(true);

  // Habilitar al terminar Turbo/Load
  document.addEventListener('turbo:load', onReady, { once: true });
  window.addEventListener('load', onReady, { once: true });
})();
