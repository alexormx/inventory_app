import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
	static targets = ["tab", "panel"]

	connect(){
		// Activar primera pestaña si ninguna activa
		if(!this.hasTabTarget) return;
		const active = this.tabTargets.find(t => t.getAttribute("aria-selected") === "true") || this.tabTargets[0];
		this.activate(active);
	}

	select(event){
		this.activate(event.currentTarget);
	}

	activate(tab){
		this.tabTargets.forEach(t => {
			const selected = t === tab;
			t.setAttribute("aria-selected", selected.toString());
			const panelId = t.getAttribute("aria-controls");
			const panel = panelId && this.element.querySelector(`#${panelId}`);
			if(panel) panel.hidden = !selected;
		});
	}
}

