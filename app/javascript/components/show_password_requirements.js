//Function to show password requirements when user enters the first character.
function showPasswordRequirements() {
  const password = document.querySelector(".pwd-input");
  const passwordRequirements = document.querySelector("#password-requirements");
  if (!password || !passwordRequirements) return;

  password.addEventListener("input", () => {
    passwordRequirements.classList.remove("d-none");
  });
}
// Run for full page loads
document.addEventListener("turbo:load", showPasswordRequirements);
document.addEventListener("turbo:render", showPasswordRequirements);