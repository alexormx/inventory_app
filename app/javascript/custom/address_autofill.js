// Simple vanilla JS CP autofill
// Usage: setupAddressAutofill({ cpInput, coloniaSelect, municipioInput, estadoInput, endpoint })

export function setupAddressAutofill({ cpInput, coloniaSelect, municipioInput, estadoInput, endpoint = '/api/postal_codes' }) {
  const cpEl = document.querySelector(cpInput)
  const colEl = document.querySelector(coloniaSelect)
  const munEl = document.querySelector(municipioInput)
  const estEl = document.querySelector(estadoInput)
  if (!cpEl || !colEl || !munEl || !estEl) return

  let timer = null
  const helpId = cpEl.id + '_cp_help'
  let helpEl = document.getElementById(helpId)
  if (!helpEl) {
    helpEl = document.createElement('div')
    helpEl.id = helpId
    helpEl.className = 'form-text'
    cpEl.parentNode.appendChild(helpEl)
  }

  function clearSelect() {
    colEl.innerHTML = '<option value="">-- Selecciona colonia --</option>'
  }

  function setLoading(state) {
    cpEl.classList.toggle('is-loading', state)
  }

  function fetchCP(cp) {
    if (!/^[0-9]{5}$/.test(cp)) {
      helpEl.textContent = 'Ingresa un CP de 5 dígitos.'
      munEl.value = ''
      estEl.value = ''
      clearSelect()
      return
    }
    setLoading(true)
    fetch(`${endpoint}?cp=${cp}`)
      .then(r => r.json())
      .then(data => {
        setLoading(false)
        if (data.error === 'invalid_cp') {
          helpEl.textContent = 'CP inválido.'
          munEl.value = ''
          estEl.value = ''
          clearSelect()
          return
        }
        if (!data.found) {
          helpEl.textContent = 'CP no encontrado.'
          munEl.value = ''
          estEl.value = ''
          clearSelect()
          return
        }
        helpEl.textContent = ''
        munEl.value = titleCase(data.municipio)
        estEl.value = titleCase(data.estado)
        clearSelect()
        data.colonias.forEach(c => {
          const opt = document.createElement('option')
          opt.value = c
          opt.textContent = titleCase(c)
          colEl.appendChild(opt)
        })
        // Pre-seleccionar si hay data-current (normalizado a minúsculas)
        const current = colEl.getAttribute('data-current')
        if (current) {
          const lowerCurrent = current.toLowerCase()
            ;[...colEl.options].forEach(o => { if (o.value.toLowerCase() === lowerCurrent) o.selected = true })
        }
      })
      .catch(err => {
        console.error('CP fetch error', err)
        setLoading(false)
        helpEl.textContent = 'Error consultando CP.'
      })
  }

  function debounceFetch() {
    clearTimeout(timer)
    timer = setTimeout(() => fetchCP(cpEl.value.trim()), 400)
  }

  cpEl.addEventListener('input', debounceFetch)
  // Autofetch si ya viene precargado el CP (edición)
  if (cpEl.value.trim().match(/^\d{5}$/)) {
    fetchCP(cpEl.value.trim())
  }

  // Helpers
  function titleCase(str) {
    return (str || '').replace(/\b\w+/g, s => s.charAt(0).toUpperCase() + s.slice(1))
  }
}
