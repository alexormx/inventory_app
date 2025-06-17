// Function to handle fading flash messages
function handleFlashMessages() {
  const flashes = document.querySelectorAll(".flash-message");
  if (!flashes.length) return;

  flashes.forEach((flash) => {
    setTimeout(() => {
      flash.classList.remove("show");
      flash.classList.add("fade");
      setTimeout(() => flash.remove(), 500);
    }, 5000);
  });
}

// Run for full page loads
document.addEventListener("turbo:load", handleFlashMessages);
// ✅ Also run for Turbo-driven updates (important!)
document.addEventListener("turbo:render", handleFlashMessages);
