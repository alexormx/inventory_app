// Function to handle fading flash messages
function handleFlashMessages() {
  const flashes = document.querySelectorAll('.flash-message');
  if(!flashes.length) return;

  flashes.forEach(flash => {
    if(flash.dataset.init) return;
    flash.dataset.init = '1';
    // Auto dismiss
  const timeout = setTimeout(()=>dismissFlash(flash), 5000);
  flash.dataset.timeoutId = timeout;
  // Debug opcional (comentable)
  // console.debug('[flash] auto-dismiss programado', flash.textContent.trim());
  });
}

function dismissFlash(el){
  if(!el || el.dataset.dismissing) return;
  el.dataset.dismissing = '1';
  if(el.dataset.timeoutId){ clearTimeout(el.dataset.timeoutId); }
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
  children.forEach((c,i)=>{ c.style.marginTop = (i===0?0:'.5rem'); });
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
document.addEventListener('turbo:load', handleFlashMessages);
// ✅ Also run for Turbo-driven updates (important!)
document.addEventListener('turbo:render', handleFlashMessages);
// ✅ Para actualizaciones via Turbo Streams (replace/update)
document.addEventListener('turbo:after-stream-render', handleFlashMessages);
// ✅ Para frames (por si se usan en el futuro)
document.addEventListener('turbo:frame-load', handleFlashMessages);
// Fallback (in case turbolinks still appears somewhere)
document.addEventListener('turbolinks:load', handleFlashMessages);
