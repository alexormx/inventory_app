// Function to handle fading flash messages
function handleFlashMessages() {
  const flashes = document.querySelectorAll('.flash-message');
  if(!flashes.length) return;

  flashes.forEach(flash => {
    // Avoid scheduling twice
    if(flash.dataset.autodismissScheduled) return;
    flash.dataset.autodismissScheduled = '1';
    // Auto dismiss after 5s
    setTimeout(()=>dismissFlash(flash), 5000);
    // Attach close button handler (Bootstrap JS not loaded)
    const btn = flash.querySelector('.btn-close');
    if(btn && !btn.dataset.bound){
      btn.addEventListener('click', e => { e.preventDefault(); dismissFlash(flash); });
      btn.dataset.bound = '1';
    }
  });
}

function dismissFlash(el){
  if(!el || el.dataset.dismissing) return;
  el.dataset.dismissing = '1';
  el.classList.remove('show');
  el.style.opacity = '0';
  setTimeout(()=> el.remove(), 400);
}

// Run for full page loads
document.addEventListener('turbo:load', handleFlashMessages);
// ✅ Also run for Turbo-driven updates (important!)
document.addEventListener('turbo:render', handleFlashMessages);
// Fallback (in case turbolinks still appears somewhere)
document.addEventListener('turbolinks:load', handleFlashMessages);
