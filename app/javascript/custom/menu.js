
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
      menu.classList.add(toggle_class);
    }
  });
}

// Function to handle fading flash messages
function handleFlashMessages() {
  const flash = document.querySelector(".flash-message");
  if (!flash) return;
  
  setTimeout(() => {
    flash.classList.remove("show");
    flash.classList.add("fade");
    setTimeout(() => flash.remove(), 500);
  }, 5000);
}

// Add toggle listeners to listen for clicks.
document.addEventListener("turbo:load", function() {
  addToggleListener("hamburger", "navbar-scroll", "collapse");
  addToggleListener("admin-hamburger", "admin-navbar", "collapse");
  addToggleListener("account",   "dropdown-menu", "active");
});

// Run for full page loads
document.addEventListener("turbo:load", handleFlashMessages);
// ✅ Also run for Turbo-driven updates (important!)
document.addEventListener("turbo:render", handleFlashMessages);


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

document.addEventListener("DOMContentLoaded", function () {
  const passwordInput = document.querySelector(".pwd-input");
  const confirmPasswordInput = document.querySelector(".pwd-conf-input");
  const submitButton = document.querySelector(".btn-pwd"); // Get the submit button
  console.log(passwordInput, confirmPasswordInput, submitButton);
  const requirements = {
    minLength: document.getElementById("minLength"),
    uppercase: document.getElementById("uppercase"),
    lowercase: document.getElementById("lowercase"),
    number: document.getElementById("number"),
    symbol: document.getElementById("symbol"),
    pswConfirmation: document.getElementById("psw-confirmation"),
  };

  function updateRequirement(element, condition) {
    const icon = element.querySelector("i");
    if (condition) {
      icon.classList.remove("fa-times", "text-danger");
      icon.classList.add("fa-check", "text-success"); // Green checkmark (Nike style)
    } else {
      icon.classList.remove("fa-check", "text-success");
      icon.classList.add("fa-times", "text-danger"); // Red X
    }
  }

  function validatePassword() {
    const password = passwordInput.value;
    const confirmPassword = confirmPasswordInput ? confirmPasswordInput.value : "";
    
    const validations = {
      minLength: password.length >= 6,
      uppercase: /[A-Z]/.test(password),
      lowercase: /[a-z]/.test(password),
      number: /\d/.test(password),
      symbol: /[\W_]/.test(password),
      pswConfirmation: password !== "" && password === confirmPassword,
    };

    // Update UI based on validation
    for (const key in validations) {
      updateRequirement(requirements[key], validations[key]);
    }

    // Enable or disable the submit button based on validation
    const allValid = Object.values(validations).every((v) => v === true);

    console.log(allValid);     
    
    if (allValid) {
      submitButton.classList.remove("disabled");
    } else {
      submitButton.classList.add("disabled");
    }
  }

  // Attach event listeners
  passwordInput.addEventListener("input", validatePassword);
  if (confirmPasswordInput) {
    confirmPasswordInput.addEventListener("input", validatePassword);
  }
});