// Menu manipulation

// Add toggle listeners to listen for clicks.
document.addEventListener("turbo:load", function() {
  let account = document.querySelector("#userDropdown");
  if(account) {
    account.addEventListener("click", function(event) {
      event.preventDefault();
      let menu = document.querySelector("#dropdownMenu");
      menu.classList.toggle("show");
    });
  }
});
