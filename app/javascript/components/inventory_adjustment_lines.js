function initInventoryAdjustmentLines(){
  if(window.__IA_LINES_LOADED){ console.log("[IA Lines] already initialized"); return; }
  window.__IA_LINES_LOADED = true;
  console.log("[IA Lines] init invoked");
  const searchInput = document.querySelector("#inventory-adjustment-product-search");
  const resultsContainer = document.querySelector("#inventory-adjustment-product-results");
  const linesTableBody = document.querySelector("#inventory-adjustment-lines-body");
  const form = document.querySelector("form.inventory_adjustment, form#new_inventory_adjustment");
  if (!searchInput) { console.log("[IA Lines] search input not found"); return; }
  if (!resultsContainer) { console.log("[IA Lines] results container not found"); return; }
  if (!linesTableBody) { console.log("[IA Lines] lines body not found"); return; }
  console.log("[IA Lines] initialization OK");

  let debounceTimer = null;
  let lineIndex = linesTableBody.querySelectorAll("tr.line-row").length;

  searchInput.addEventListener("input", (e) => {
    clearTimeout(debounceTimer);
    const q = e.target.value.trim();
    if (q.length < 3) { resultsContainer.innerHTML = ""; return; }
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
    debounceTimer = setTimeout(() => {
      const url = `/admin/products/search?query=${encodeURIComponent(q)}`;
      console.log("[IA Lines] fetching", url);
      fetch(url, {
        headers: { "Accept": "application/json", "X-CSRF-Token": token }
      }).then(r => {
        console.log("[IA Lines] response status", r.status);
        return r.json();
      }).then(products => {
        console.log("[IA Lines] products returned", products.length);
        resultsContainer.innerHTML = "";
        products.forEach(p => {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "list-group-item list-group-item-action";
          btn.innerHTML = `<div class='d-flex align-items-center'>`+
            (p.thumbnail_url ? `<img src='${p.thumbnail_url}' class='me-2 rounded' width='32' height='32'/>` : "") +
            `<div><strong>${p.product_name}</strong><br><small class='text-muted'>SKU: ${p.product_sku}</small></div></div>`;
          btn.addEventListener("click", () => { addLineForProduct(p); resultsContainer.innerHTML = ""; searchInput.value = ""; });
          resultsContainer.appendChild(btn);
        });
  }).catch(err => console.error("[IA Lines] fetch error", err));
    }, 300);
  });

  function addLineForProduct(product) {
    const tr = document.createElement("tr");
  tr.className = "line-row";
  tr.dataset.productId = product.id;
  tr.dataset.lineUid = `${product.id}-${Date.now()}-${Math.random().toString(36).slice(2,8)}`;

  tr.innerHTML = `
      <td>
        <input type='hidden' name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][product_id]' value='${product.id}' class='product-id-input'/>
        <span class='small text-muted product-name'>${product.product_name}</span><br/>
        <small class='text-muted'>${product.product_sku}</small>
      </td>
      <td>
        <select name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][direction]' class='form-select direction-select'>
          <option value='increase'>Increase</option>
          <option value='decrease'>Decrease</option>
        </select>
      </td>
      <td style='width:110px'>
        <input type='number' min='1' value='1' class='form-control quantity-input' name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][quantity]' />
      </td>
      <td>
        <select name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][reason]' class='form-select reason-select d-none'>
          <option value=''>Select</option>
          <option value='scrap'>Scrap</option>
          <option value='marketing'>Marketing</option>
          <option value='lost'>Lost</option>
          <option value='damaged'>Damaged</option>
        </select>
      </td>
      <td style='width:140px'>
        <input type='number' step='0.01' class='form-control unit-cost-input' name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][unit_cost]' />
      </td>
      <td>
        <input type='text' class='form-control note-input' name='inventory_adjustment[inventory_adjustment_lines_attributes][${lineIndex}][note]' />
      </td>
      <td>
        <button type='button' class='btn btn-sm btn-outline-danger remove-line' title='Remove line'>&times;</button>
      </td>
    `;

    linesTableBody.appendChild(tr);
  // Remove placeholder if present
  const ph = document.getElementById("no-lines-placeholder");
  if (ph) ph.remove();
    lineIndex++;
  }

  // Delegated events
  linesTableBody.addEventListener("change", (e) => {
    if (e.target.classList.contains("direction-select")) {
      const row = e.target.closest("tr");
      const reasonSelect = row.querySelector(".reason-select");
      if (e.target.value === "decrease") {
        reasonSelect.classList.remove("d-none");
      } else {
        reasonSelect.classList.add("d-none");
        reasonSelect.value = "";
      }
    }
  });

  linesTableBody.addEventListener("click", (e) => {
    if (e.target.classList.contains("remove-line")) {
      const row = e.target.closest("tr");
      row.remove();
      // If no lines remain, show placeholder again
      if (!linesTableBody.querySelector("tr.line-row")) {
        const placeholder = document.createElement("tr");
        placeholder.id = "no-lines-placeholder";
        placeholder.className = "text-muted";
        placeholder.innerHTML = `<td colspan='7'><em>No lines yet. Use the search box above to add products.</em></td>`;
        linesTableBody.appendChild(placeholder);
        // allow re-init if user added/removed all
        window.__IA_LINES_LOADED = true; // keep flag
      }
    }
  });
}

document.addEventListener("turbo:load", initInventoryAdjustmentLines);
document.addEventListener("DOMContentLoaded", () => {
  setTimeout(() => { if(!window.__IA_LINES_LOADED) initInventoryAdjustmentLines(); }, 50);
});

window.forceInitInventoryAdjustmentLines = initInventoryAdjustmentLines;
