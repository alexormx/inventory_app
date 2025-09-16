import "@hotwired/turbo-rails"
import "./controllers"   // index.js arranca Stimulus y registra todo

// --- Legacy vanilla helpers (aún no migrados a Stimulus) ---
// Dropdown toggles based on data-dropdown-* attributes
// (Migrated dropdowns to Stimulus: legacy script removed)
// Cart preview hover/focus panel logic
import "./custom/cart_preview"

// (Opcional: inicializaciones globales no atadas a Stimulus)
// TEMP: enable debug while troubleshooting product-search controller not connecting
window.APP_DEBUG = true

// ---- Stimulus controller registration verification + dynamic fallback registration ----
// If for some reason the static import tree missed product_search_controller, attempt a dynamic import
window.addEventListener('DOMContentLoaded', () => {
	try {
		const stim = window.Stimulus
		const hasStimulus = !!stim
		const registered = hasStimulus ? Array.from(stim.router.modules.map(m => m.identifier)) : []
		if(window.APP_DEBUG) console.log('[bootstrap] Stimulus present:', hasStimulus, 'identifiers:', registered)

		const needsDynamic = hasStimulus && !registered.includes('product-search')
		if (needsDynamic) {
			if(window.APP_DEBUG) console.log('[bootstrap] product-search missing; attempting dynamic import fallback')
			import('./controllers/product_search_controller').then(mod => {
				try {
					const Controller = mod.default
					stim.register('product-search', Controller)
					console.log('[bootstrap] product-search dynamically registered')
				} catch(e) {
					console.error('[bootstrap] failed dynamic registration', e)
				}
			}).catch(e => console.error('[bootstrap] dynamic import failed', e))
		}
	} catch(e) {
		console.error('[bootstrap] error inspecting Stimulus registry', e)
	}
})

// ---- Vanilla DOM fallback if Stimulus still not attaching after a short delay ----
setTimeout(() => {
	try {
		const wrappers = document.querySelectorAll('[data-controller~="product-search"]')
		if(!wrappers.length) return

		wrappers.forEach(wrapper => {
			if (wrapper.dataset.productSearchAttached) return // Stimulus connected
			if (wrapper.dataset.productSearchFallback) return // already attached fallback

			// Basic targets
			const input = wrapper.querySelector('[data-product-search-target="input"], input[type="search"], input')
			const results = wrapper.querySelector('[data-product-search-target="results"], [data-product-search-results], .product-search-results')
			if(!input || !results) return

			const url = wrapper.getAttribute('data-product-search-url-value') || '/admin/products/search'
			const minLength = parseInt(wrapper.getAttribute('data-product-search-min-length-value') || '3', 10)
			let t
			function renderInfo(msg){ results.innerHTML = `<div class="text-xs text-gray-500 p-2">${msg}</div>` }
			function renderErr(msg){ results.innerHTML = `<div class="text-xs text-red-600 p-2">${msg}</div>` }
			function renderProducts(list){
				if(!Array.isArray(list) || !list.length){ renderInfo('No results'); return }
				results.innerHTML = list.map(p => `<button type="button" data-id="${p.id}" class="block w-full text-left px-2 py-1 hover:bg-indigo-50 text-sm">${p.sku || ''} ${p.name || ''}</button>`).join('')
			}
			async function doSearch(q){
				try {
					const endpoint = `${url}?q=${encodeURIComponent(q)}`
					if(window.APP_DEBUG) console.log('[product-search:fallback] fetch', endpoint)
					const r = await fetch(endpoint, { headers: { 'Accept': 'application/json' } })
					if(!r.ok) throw new Error(r.status)
						const data = await r.json()
						renderProducts(data)
				} catch(e) { renderErr('Error'); console.error('[product-search:fallback] error', e) }
			}
			input.addEventListener('input', () => {
				const q = input.value.trim()
				if(q.length < minLength){
					results.innerHTML = ''
					if(q.length === 0) renderInfo(`Type at least ${minLength} characters`)
					return
				}
				clearTimeout(t)
				results.innerHTML = '<div class="text-xs text-gray-500 p-2">Searching...</div>'
				t = setTimeout(() => doSearch(q), 250)
			})
			wrapper.dataset.productSearchFallback = '1'
			window.PRODUCT_SEARCH_FALLBACK_ACTIVE = true
			if(window.APP_DEBUG) console.log('[product-search:fallback] attached')
		})
	} catch(e) {
		console.error('[product-search:fallback] setup failure', e)
	}
}, 800) // give Stimulus a moment first

