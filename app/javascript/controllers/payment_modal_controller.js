import { Controller } from "@hotwired/stimulus"

// Controlador placeholder para modales de pago.
// Actualmente no hace nada porque el flujo de apertura lo maneja custom/payment_modal.js,
// pero mantenerlo evita errores si está registrado en index.js y no hay implementación.
export default class extends Controller {
	connect() {
		// No-op por ahora. Punto de extensión para lógica futura.
	}
}
