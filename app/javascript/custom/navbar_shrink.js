// Navbar shrink on scroll
(function(){
  const nav = document.querySelector('.site-navbar');
  if(!nav) return;
  const toggle = () => {
    if(window.scrollY > 40) {
      nav.classList.add('shrink');
    } else {
      nav.classList.remove('shrink');
    }
  };
  document.addEventListener('turbo:load', toggle);
  document.addEventListener('turbo:render', toggle);
  window.addEventListener('scroll', toggle, { passive: true });
})();
