import { Controller } from "@hotwired/stimulus"

// Stimulus product search controller
// Usage: parent element wraps the input + results and has:
//   data-controller="product-search"
//   optional: data-product-search-url-value
//   optional: data-product-search-min-length-value
// Targets:
//   data-product-search-target="input"
//   data-product-search-target="results"
// Dispatches event: product-search:selected with detail = product object
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: { type: String, default: "/admin/products/search" }, minLength: { type: Number, default: 2 } }

  connect(){
    this._timer = null
  }

  input(){
    const q = this.inputTarget.value.trim()
    if(q.length < this.minLengthValue){
      this.showInfo(`Type at least ${this.minLengthValue} characters (${q.length}/${this.minLengthValue}).`)
      return
    }
    clearTimeout(this._timer)
    this.showLoading()
    this._timer = setTimeout(()=> this.performSearch(q), 300)
  }

  performSearch(query){
    const url = `${this.urlValue}?query=${encodeURIComponent(query)}`
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, { headers: { 'Accept':'application/json', 'X-CSRF-Token': token }})
      .then(r => { if(!r.ok) throw new Error(`HTTP ${r.status}`); return r.json() })
      .then(products => this.render(products))
      .catch(err => this.renderError(err))
  }

  render(products){
    this.resultsTarget.innerHTML = ''
    if(!Array.isArray(products)) return this.renderError(new Error('Invalid response'))
    if(products.length === 0) return this.showInfo('No products found')
    products.forEach(p => {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'list-group-item list-group-item-action'
      
      // Build stock info if available (for sale orders)
      let stockInfo = ''
      if (p.stock_available !== undefined) {
        const stockClass = p.stock_available > 0 ? 'text-success' : 'text-danger'
        stockInfo = `<span class="ms-2 small ${stockClass}"><i class="bi bi-box-seam"></i> ${p.stock_available} disp.</span>`
        if (p.stock_reserved > 0) {
          stockInfo += `<span class="ms-1 small text-warning"><i class="bi bi-bookmark"></i> ${p.stock_reserved} apt.</span>`
        }
      }
      
      btn.innerHTML = `<div class='d-flex align-items-center'>${p.thumbnail_url ? `<img src='${p.thumbnail_url}' class='me-2 rounded' width='40' height='40'/>` : ''}<div class="flex-grow-1"><strong>${p.product_name}</strong>${stockInfo}<br><small class='text-muted'>SKU: ${p.product_sku}</small></div></div>`
      btn.addEventListener('click', ()=>{
        this.dispatch('selected', { detail: p })
        this.resultsTarget.innerHTML = ''
        this.inputTarget.value = ''
        this.inputTarget.focus()
      })
      this.resultsTarget.appendChild(btn)
    })
  }

  renderError(err){
    this.resultsTarget.innerHTML = ''
    const div = document.createElement('div')
    div.className = 'list-group-item list-group-item-danger text-danger'
    div.textContent = `Search error: ${err.message}`
    this.resultsTarget.appendChild(div)
  }

  showLoading(){
    this.resultsTarget.innerHTML = ''
    const div = document.createElement('div')
    div.className = 'list-group-item text-muted'
    div.textContent = 'Searching...'
    this.resultsTarget.appendChild(div)
  }

  showInfo(message){
    this.resultsTarget.innerHTML = ''
    const div = document.createElement('div')
    div.className = 'list-group-item text-muted'
    div.textContent = message
    this.resultsTarget.appendChild(div)
  }
}
