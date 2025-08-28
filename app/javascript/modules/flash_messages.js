// Function to handle fading flash messages
function handleFlashMessages() {
  const flashes = document.querySelectorAll('.flash-message');
  flashes.forEach(scheduleFlash);
}

function scheduleFlash(flash){
  if(!flash || flash.dataset.init) return;
  flash.dataset.init = '1';
  // Duración configurable vía data-timeout (ms) o default 5000
  const delay = parseInt(flash.dataset.timeout || '3000', 10);
  flash.__flashTimeoutId = setTimeout(()=> dismissFlash(flash), delay);
}

function dismissFlash(el){
  if(!el || el.dataset.dismissing) return;
  el.dataset.dismissing = '1';
  if(el.__flashTimeoutId){ clearTimeout(el.__flashTimeoutId); }
  requestAnimationFrame(()=>{
    el.style.transition = 'opacity .35s ease, transform .35s ease';
    el.style.opacity = '0';
    el.style.transform = 'translateY(-6px)';
    setTimeout(()=>{ el.remove(); adjustStack(); }, 360);
  });
}

function adjustStack(){
  const container = document.querySelector('#flash');
  if(!container) return;
  const children = Array.from(container.querySelectorAll('.flash-message'));
  // Asegura orden natural (primer insert arriba) manteniendo flex-end alignment
  children.forEach((c,i)=>{ c.style.marginTop = '.5rem'; });
  if(children[0]) children[0].style.marginTop = 0;
}

// Delegated click (captura X aunque se reemplace el nodo)
document.addEventListener('click', (e)=>{
  const btn = e.target.closest('.flash-message .btn-close');
  if(btn){
    e.preventDefault();
    const el = btn.closest('.flash-message');
    dismissFlash(el);
  }
});

// Run for full page loads
['turbo:load','turbo:render','turbo:after-stream-render','turbo:frame-load','turbolinks:load'].forEach(ev=>{
  document.addEventListener(ev, ()=> setTimeout(handleFlashMessages, 0));
});

// MutationObserver para capturar reemplazos dinámicos (Turbo Streams)
const mo = new MutationObserver(mutations => {
  let found = false;
  mutations.forEach(m => {
    m.addedNodes.forEach(n => {
      if(n.nodeType === 1){
        if(n.classList.contains('flash-message')) { scheduleFlash(n); found = true; }
        n.querySelectorAll && n.querySelectorAll('.flash-message').forEach(f=>{ scheduleFlash(f); found = true; });
      }
    });
  });
  if(found) adjustStack();
});
mo.observe(document.documentElement, { childList: true, subtree: true });

// Inicial
setTimeout(handleFlashMessages, 0);
