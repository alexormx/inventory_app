function disableEnterUntilEmail() {
  const emailInput = document.querySelector(".email-input"); // get the email input
  const form = emailInput.closest("form"); // Get the closest form
  
  if (!emailInput || !form) return;

  // Validate email format
  function isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  // Prevent Enter key if email is empty or invalid
  form.addEventListener("keydown", function (event) {
    if (event.key === "Enter" && !isValidEmail(emailInput.value)) {
      event.preventDefault();
    }
  });
}

// Run for full page loads
document.addEventListener("turbo:load", disableEnterUntilEmail);
// ✅ Also run for Turbo-driven updates (important!)
document.addEventListener("turbo:render", disableEnterUntilEmail);