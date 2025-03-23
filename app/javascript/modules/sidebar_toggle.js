// app/javascript/custom/sidebar_toggle.js
// convert this to a function that runs when the DOM is loaded
function toggleSidebar() {
  const toggleBtn = document.getElementById("sidebarToggle");
  const sidebar = document.getElementById("sidebar");

  if (!toggleBtn || !sidebar) {
    return;
  }

  // ➤ Check if sidebar should start collapsed
  if (localStorage.getItem("sidebar-collapsed") === "true") {
    collapseSidebar();
  }

  // ➤ Toggle sidebar and save state
  toggleBtn.addEventListener("click", () => {
    if (sidebar.classList.contains("sidebar-collapsed")) {
      expandSidebar();
    } else {
      collapseSidebar();
    }
  });
  function collapseSidebar() {
    sidebar.classList.add("sidebar-collapsed");
    document.querySelectorAll(".sidebar-label").forEach(label => label.classList.add("d-none"));
    localStorage.setItem("sidebar-collapsed", "true");
  }

  function expandSidebar() {
    sidebar.classList.remove("sidebar-collapsed");
    document.querySelectorAll(".sidebar-label").forEach(label => label.classList.remove("d-none"));
    localStorage.setItem("sidebar-collapsed", "false");
  }
}

// Run for full page loads
document.addEventListener("turbo:load", toggleSidebar);
