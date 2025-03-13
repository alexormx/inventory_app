// app/javascript/controllers/navbar_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu", "dropdown"];

  toggleMenu() {
    this.menuTarget.classList.toggle("is-active");
  }

  toggleDropdown(event) {
    event.preventDefault();
    this.dropdownTarget.classList.toggle("is-active");
  }
}