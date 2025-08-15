// app/javascript/custom/sidebar_toggle.js
// convert this to a function that runs when the DOM is loaded
function toggleSidebar() {
  const toggleBtn = document.getElementById("sidebarToggle");
  const sidebar = document.getElementById("sidebar");

  if (!toggleBtn || !sidebar) {
    return;
  }

  // Estado ya aplicado por script inline para evitar flash; solo sincronizamos labels
  syncLabels();

  // ➤ Toggle sidebar and save state
  toggleBtn.addEventListener("click", () => {
    const collapsed = document.documentElement.classList.toggle("sidebar-collapsed");
    localStorage.setItem("sidebar-collapsed", collapsed ? "true" : "false");
    syncLabels();
  });

  function syncLabels() {
    const isCollapsed = document.documentElement.classList.contains("sidebar-collapsed");
    document.querySelectorAll(".sidebar-label").forEach(label => label.classList.toggle("d-none", isCollapsed));
  }
}

// Run for full page loads
document.addEventListener("turbo:load", toggleSidebar);
