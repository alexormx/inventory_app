// Ajusta la flecha del preview para alinearse bajo el enlace del carrito y refresca tras cambios
(function(){
  const STATE='__cartPreviewDyn'; if(window[STATE]) return; window[STATE]=true;
  function align(){
    const link = document.querySelector('.site-navbar a[href*="/cart"]');
    const panel = document.getElementById('cart-preview');
    if(!link || !panel) return;
    const linkRect = link.getBoundingClientRect();
    const panelRect = panel.getBoundingClientRect();
    // Calcular offset desde borde derecho del panel hasta el centro aproximado del icono carrito
    const icon = link.querySelector('i');
    const iconCenter = icon ? (icon.getBoundingClientRect().left + icon.getBoundingClientRect().width/2) : (linkRect.left + linkRect.width/2);
    const panelRight = panelRect.left + panelRect.width;
    const offset = Math.min(Math.max(panelRight - iconCenter - 7, 12), panelRect.width - 24); // clamp
    panel.style.setProperty('--arrow-offset', offset + 'px');
  }
  function refresh(){ align(); }
  ['resize','scroll'].forEach(ev=> window.addEventListener(ev, align, {passive:true}));
  document.addEventListener('turbo:load', align);
  document.addEventListener('turbo:render', align);
  document.addEventListener('mouseover', e=>{ if(e.target.closest('#cart-preview') || e.target.closest('a[href*="/cart"]')) align(); });
})();
