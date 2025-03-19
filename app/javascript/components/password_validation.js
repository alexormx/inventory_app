function passwordValidationMain() {
  const passwordInput = document.querySelector(".pwd-input");
  const confirmPasswordInput = document.querySelector(".pwd-conf-input");
  const submitButton = document.querySelector(".btn-pwd"); // Get the submit button
  if (!passwordInput || !submitButton | !confirmPasswordInput) return;

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
    
    if (allValid) {
      submitButton.classList.remove("disabled");
    } else {
      submitButton.classList.add("disabled");
    }
  }

  // Handle `field_with_errors` from Devise and reinitialize fields
  function removeFieldErrors() {
    document.querySelectorAll(".field_with_errors input, .field_with_errors label").forEach((field) => {
      const parent = field.parentElement;
      parent.replaceChild(field.cloneNode(true), field);
    });
  }

  removeFieldErrors(); // Cleanup error fields before adding events

  // Attach event listeners
  passwordInput.addEventListener("input", validatePassword);
  if (confirmPasswordInput) {
    confirmPasswordInput.addEventListener("input", validatePassword);
  }
};

document.addEventListener("DOMContentLoaded", passwordValidationMain);
document.addEventListener("turbo:load", passwordValidationMain);
document.addEventListener("turbo:render", passwordValidationMain);
