import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
	static targets = ["section"]

	toggle(event){
		const header = event.currentTarget;
		const content = header.nextElementSibling;
		if(!content) return;
		const expanded = header.getAttribute("aria-expanded") === "true";
		header.setAttribute("aria-expanded", (!expanded).toString());
		content.hidden = expanded;
	}
}

