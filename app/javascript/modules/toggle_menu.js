// Adds a toggle listener.
function addToggleListener(selected_id, menu_id, toggle_class) {
  const selected_element = document.querySelector(`#${selected_id}`);
  const menu = document.querySelector(`#${menu_id}`)
  
  if(!selected_element || !menu) return;

  // Function to toggle visibility
  const toggleMenu = (event) => {
    event.preventDefault();
    event.stopPropagation();
    menu.classList.toggle(toggle_class);
  };

  selected_element.addEventListener("click", toggleMenu);

  // ✅ Hide menu when clicking outside
  document.addEventListener('click', (event) =>  {
    const clickedOutsideMenu  = !menu.contains(event.target);
    const clickedOutsideButton  = !selected_element.contains(event.target);

    if (clickedOutsideMenu && clickedOutsideButton) {
      menu.classList.remove(toggle_class);
    }
  });
}

// Add toggle listeners to listen for clicks.
document.addEventListener("turbo:load", function() {
  addToggleListener("hamburger", "navbar-scroll", "collapse");
  addToggleListener("admin-hamburger", "admin-navbar", "collapse");
  addToggleListener("account",   "dropdown-menu", "active");
});
