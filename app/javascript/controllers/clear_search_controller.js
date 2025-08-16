import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Se espera data-action="click->clear-search#clear" en el botón
  clear(event) {
    const form = event.currentTarget.closest('form')
    if (!form) return
    const q = form.querySelector('input[name="q"]')
    if (q) q.value = ''
    form.requestSubmit()
  }
}
