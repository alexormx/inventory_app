// app/javascript/custom/sidebar_toggle.js
// convert this to a function that runs when the DOM is loaded
function toggleSidebar() {
  const sidebar = document.getElementById("sidebar");
  if (!sidebar) return;

  const toggleBtns = document.querySelectorAll('[data-sidebar-toggle], .js-sidebar-toggle, #sidebarToggle');
  if (!toggleBtns.length) return;

  syncLabels();

  toggleBtns.forEach(btn => {
    btn.setAttribute('aria-controls', 'sidebar');
    btn.setAttribute('aria-expanded', String(!document.documentElement.classList.contains('sidebar-collapsed')));
    btn.addEventListener("click", () => {
      const collapsed = document.documentElement.classList.toggle("sidebar-collapsed");
      localStorage.setItem("sidebar-collapsed", collapsed ? "true" : "false");
      toggleBtns.forEach(b => b.setAttribute('aria-expanded', String(!collapsed)));
      syncLabels();
    });
  });

  function syncLabels() {
    const isCollapsed = document.documentElement.classList.contains("sidebar-collapsed");
    document.querySelectorAll(".sidebar-label").forEach(label => label.classList.toggle("d-none", isCollapsed));
  }
}

// Run for full page loads
document.addEventListener("turbo:load", toggleSidebar);
