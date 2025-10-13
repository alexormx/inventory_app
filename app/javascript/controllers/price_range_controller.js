import { Controller } from "@hotwired/stimulus"
import noUiSlider from "nouislider"

export default class extends Controller {
  static targets = ["slider", "minInput", "maxInput", "minDisplay", "maxDisplay"]
  static values = {
    min: { type: Number, default: 0 },
    max: { type: Number, default: 10000 },
    currentMin: { type: Number, default: 0 },
    currentMax: { type: Number, default: 10000 }
  }

  connect() {
    // Inicializar valores actuales desde los inputs si existen
    if (this.hasMinInputTarget && this.minInputTarget.value) {
      this.currentMinValue = parseFloat(this.minInputTarget.value)
    }
    if (this.hasMaxInputTarget && this.maxInputTarget.value) {
      this.currentMaxValue = parseFloat(this.maxInputTarget.value)
    }

    // Crear el slider
    this.initializeSlider()

    // Escuchar cambios en los inputs para actualizar el slider
    if (this.hasMinInputTarget) {
      this.minInputTarget.addEventListener('input', this.updateSliderFromInputs.bind(this))
    }
    if (this.hasMaxInputTarget) {
      this.maxInputTarget.addEventListener('input', this.updateSliderFromInputs.bind(this))
    }
  }

  disconnect() {
    if (this.slider) {
      this.slider.destroy()
    }
  }

  initializeSlider() {
    if (!this.hasSliderTarget) return

    const start = [this.currentMinValue, this.currentMaxValue]

    this.slider = noUiSlider.create(this.sliderTarget, {
      start: start,
      connect: true,
      range: {
        'min': this.minValue,
        'max': this.maxValue
      },
      step: 1,
      format: {
        to: (value) => Math.round(value),
        from: (value) => Number(value)
      },
      tooltips: [
        { to: (value) => `$${Math.round(value)}` },
        { to: (value) => `$${Math.round(value)}` }
      ]
    })

    // Actualizar inputs cuando cambia el slider
    this.slider.on('update', (values, handle) => {
      const minVal = values[0]
      const maxVal = values[1]

      // Actualizar inputs ocultos
      if (this.hasMinInputTarget) {
        this.minInputTarget.value = minVal
      }
      if (this.hasMaxInputTarget) {
        this.maxInputTarget.value = maxVal
      }

      // Actualizar displays si existen
      if (this.hasMinDisplayTarget) {
        this.minDisplayTarget.textContent = `$${minVal}`
      }
      if (this.hasMaxDisplayTarget) {
        this.maxDisplayTarget.textContent = `$${maxVal}`
      }
    })

    // Trigger submit cuando termina de mover (debounced automáticamente)
    this.slider.on('change', (values, handle) => {
      // Disparar evento input en los campos para que el controller de filtros lo capture
      if (this.hasMinInputTarget) {
        const event = new Event('input', { bubbles: true })
        this.minInputTarget.dispatchEvent(event)
      }
    })
  }

  updateSliderFromInputs() {
    if (!this.slider) return

    const minVal = this.hasMinInputTarget && this.minInputTarget.value
      ? parseFloat(this.minInputTarget.value)
      : this.minValue
    const maxVal = this.hasMaxInputTarget && this.maxInputTarget.value
      ? parseFloat(this.maxInputTarget.value)
      : this.maxValue

    this.slider.set([minVal, maxVal])
  }

  // Método para sincronizar desde eventos externos (cuando se limpia o cambia via chips)
  syncFromUrl(minVal, maxVal) {
    const min = minVal !== null && minVal !== undefined && minVal !== '' ? parseFloat(minVal) : this.minValue
    const max = maxVal !== null && maxVal !== undefined && maxVal !== '' ? parseFloat(maxVal) : this.maxValue

    if (this.slider) {
      this.slider.set([min, max])
    }

    if (this.hasMinInputTarget) {
      this.minInputTarget.value = minVal || ''
    }
    if (this.hasMaxInputTarget) {
      this.maxInputTarget.value = maxVal || ''
    }
  }
}
