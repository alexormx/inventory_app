import { Controller } from "@hotwired/stimulus"

// Controller for handling the discontinued toggle with price modal
export default class extends Controller {
  static values = {
    productId: Number,
    currentState: Boolean
  }

  toggle(event) {
    const checkbox = event.target
    const willBeDiscontinued = checkbox.checked
    const productId = this.productIdValue

    if (!productId) {
      alert("Guarda el producto primero antes de marcarlo como descontinuado")
      checkbox.checked = this.currentStateValue
      return
    }

    if (willBeDiscontinued) {
      // Ask for new MISB price
      const newPrice = prompt(
        "Las piezas nuevas se convertirán a MISB (Mint In Sealed Box).\n\n" +
        "Ingrese el nuevo precio para las piezas MISB:",
        ""
      )

      if (newPrice === null) {
        // User cancelled
        checkbox.checked = false
        return
      }

      const price = parseFloat(newPrice)
      if (isNaN(price) || price <= 0) {
        alert("Por favor ingrese un precio válido mayor a 0")
        checkbox.checked = false
        return
      }

      this.discontinueProduct(productId, price, checkbox)
    } else {
      // Reversing discontinuation
      const restorePrice = prompt(
        "¿Desea restaurar las piezas MISB a Nuevas?\n\n" +
        "Ingrese el nuevo precio (o deje vacío para usar el precio del producto):",
        ""
      )

      if (restorePrice === null) {
        // User cancelled
        checkbox.checked = true
        return
      }

      const price = restorePrice ? parseFloat(restorePrice) : null
      if (restorePrice && (isNaN(price) || price <= 0)) {
        alert("Por favor ingrese un precio válido mayor a 0")
        checkbox.checked = true
        return
      }

      this.reverseDiscontinuation(productId, price, checkbox)
    }
  }

  async discontinueProduct(productId, price, checkbox) {
    try {
      const response = await fetch(`/admin/products/${productId}/discontinue`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ new_price: price })
      })

      const data = await response.json()

      if (response.ok) {
        // Update UI to reflect the change
        this.currentStateValue = true
        this.updateCardStyle(true)
        alert(`Producto descontinuado exitosamente.\n${data.affected_count} piezas convertidas a MISB.`)

        // Reload to see updated inventory
        if (data.affected_count > 0) {
          window.location.reload()
        }
      } else {
        checkbox.checked = false
        alert(`Error: ${data.error || 'No se pudo descontinuar el producto'}`)
      }
    } catch (error) {
      checkbox.checked = false
      alert(`Error de conexión: ${error.message}`)
    }
  }

  async reverseDiscontinuation(productId, price, checkbox) {
    try {
      const response = await fetch(`/admin/products/${productId}/reverse_discontinue`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ restore_price: price })
      })

      const data = await response.json()

      if (response.ok) {
        // Update UI to reflect the change
        this.currentStateValue = false
        this.updateCardStyle(false)
        alert(`Producto restaurado exitosamente.\n${data.affected_count} piezas convertidas a Nuevas.`)

        // Reload to see updated inventory
        if (data.affected_count > 0) {
          window.location.reload()
        }
      } else {
        checkbox.checked = true
        alert(`Error: ${data.error || 'No se pudo restaurar el producto'}`)
      }
    } catch (error) {
      checkbox.checked = true
      alert(`Error de conexión: ${error.message}`)
    }
  }

  updateCardStyle(isDiscontinued) {
    const card = this.element.closest('.card')
    if (!card) return

    if (isDiscontinued) {
      card.classList.remove('border-warning')
      card.classList.add('border-danger', 'bg-danger', 'bg-opacity-10')
    } else {
      card.classList.remove('border-danger', 'bg-danger', 'bg-opacity-10')
      card.classList.add('border-warning')
    }
  }
}
