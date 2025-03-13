import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu", "button"]
  
  connect() {
    // ✅ Add event listener to the button dynamically
    this.buttonTarget.addEventListener("click", this.toggle.bind(this));

    // ✅ Close dropdown when clicking outside
    document.addEventListener("click", this.closeMenu.bind(this));
  }

  toggle(event) {
    event.preventDefault();
    event.stopPropagation();
    this.menuTarget.classList.toggle("show");
  }

  closeMenu(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.remove("show");
    }
  }
  
  disconnect() {
    // ✅ Remove event listener when Stimulus controller is disconnected
    this.buttonTarget.removeEventListener("click", this.toggle.bind(this));
    document.removeEventListener("click", this.closeMenu.bind(this));
  }
}