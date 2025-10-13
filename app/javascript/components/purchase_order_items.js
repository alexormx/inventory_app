// Adaptación: soportar formularios que usan prefijo "order_" (partial genérico)
// además de los IDs originales con prefijo "purchase_order_". Sin esto
// los campos no se encontraban y los costos compuestos quedaban en 0.
function fieldByName(name) {
  return document.querySelector(`#purchase_order_${name}`) || document.querySelector(`#order_${name}`);
}

function numField(name) {
  const el = fieldByName(name);
  return parseFloat(el?.value) || 0;
}

document.addEventListener("turbo:load", () => {
  const searchInput = document.querySelector("#product-search");
  const resultsContainer = document.querySelector("#product-search-results");

  if (!searchInput || !resultsContainer) return;

  let timeout = null;

  searchInput.addEventListener("input", (e) => {
    clearTimeout(timeout);
    const query = e.target.value.trim();

    if (query.length < 2) {
      resultsContainer.innerHTML = "";
      return;
    }
    const token = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
    timeout = setTimeout(() => {
      fetch(`/admin/products/search?query=${encodeURIComponent(query)}`, {
        method: "GET",
        headers: {
          "X-CSRF-Token": token,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })
        .then(res => res.json())
        .then(products => {
          resultsContainer.innerHTML = "";

          products.forEach(product => {
            const item = buildProductSearchItem(product);

            item.addEventListener("click", () => {
              const event = new CustomEvent("product:selected", { detail: product });
              document.dispatchEvent(event);
              resultsContainer.innerHTML = "";
              searchInput.value = "";
            });

            resultsContainer.appendChild(item);
          });
        });
    }, 300); // debounce
  });
});

function createElementWithClasses(tag, classes = [], options = {}) {
  const el = document.createElement(tag);
  el.classList.add(...classes);
  if (options.text) el.textContent = options.text;
  if (options.src) el.src = options.src;
  if (options.alt) el.alt = options.alt;
  if (options.html) el.innerHTML = options.html;
  return el;
}

function buildProductSearchItem(product) {
  const item = createElementWithClasses("button", ["list-group-item", "list-group-item-action"]);
  const container = createElementWithClasses("div", ["d-flex", "align-items-center"]);

  const img = createElementWithClasses("img", ["me-2", "rounded", "product-order-image"], {
    src: product.thumbnail_url,
    alt: product.product_name
  });

  const textContainer = document.createElement("div");
  textContainer.appendChild(createElementWithClasses("strong", [], { text: product.product_name }));
  textContainer.appendChild(createElementWithClasses("small", ["text-muted", "d-block"], {
    text: `SKU: ${product.product_sku}`
  }));

  container.append(img, textContainer);
  item.appendChild(container);
  item.dataset.product = JSON.stringify(product);
  return item;
}

document.addEventListener("turbo:load", () => {
  const resultsBox = document.querySelector("#product-search-results");
  const tbody = document.querySelector("#purchase-order-items-table tbody") || document.querySelector("#order-items-table tbody");
  const contextElement = document.querySelector(".order-context");
  const context = contextElement?.dataset?.context || "default";
  let index = tbody?.children.length || 0;

  if (!resultsBox || !tbody || context !== "purchase-order") return;

  // Helper para agregar producto a la tabla de PO
  function addProductToPO(product) {
    const row = buildBlankPurchaseOrderItemRow(index);

    // Fill in product details
    row.querySelector(".item-product-id").value = product.id;
    row.querySelector(".item-product-name").textContent = product.product_name;
    row.querySelector(".item-qty").value = 1;
    // Unit cost inicial en blanco/0 hasta que el usuario lo defina
    row.querySelector(".item-unit-cost").value = 0;

    // Fill volume and weight fields
    const volume = (product.unit_volume_cm3 ?? (product.length_cm * product.width_cm * product.height_cm)) || 0;
    const volumeField = row.querySelector(".item-volume");
    if (volumeField) {
      volumeField.value = volume.toFixed(2);
      volumeField.dataset.unitVolume = volume;
    }

    const weightField = row.querySelector(".item-weight");
    const weight = (product.unit_weight_gr ?? product.weight_gr) || 0;
    if (weightField) {
      weightField.value = weight.toFixed(2);
      weightField.dataset.unitWeight = weight;
    }

    if (volume === 0) {
      row.classList.add("missing-volume");
      if (volumeField) {
        volumeField.classList.add("text-warning");
        volumeField.title = "Este producto tiene volumen 0; no recibirá distribución de costos adicionales.";
      }
    }

    // Remove placeholder row si existe
    const placeholderRow = document.querySelector("#purchase-without-items");
    if (placeholderRow) placeholderRow.remove();

    tbody.appendChild(row);
    index++;

    // Clear search UI
    const si = document.querySelector("#product-search");
    if (si) si.value = "";
    resultsBox.innerHTML = "";

    // Trigger updates en orden
    updateLineTotals(row);
    updateItemTotals();
  }

  // Nota: no adjuntamos listener de click directo aquí para evitar dobles inserciones.
  // Usamos únicamente los eventos personalizados emitidos por el buscador.

  // Soportar evento global product:selected (otros módulos de búsqueda)
  document.addEventListener("product:selected", (ev) => {
    const product = ev.detail;
    if (!product) return;
    addProductToPO(product);
  });

  // Soportar evento emitido por el controller Stimulus product-search
  // Algunos componentes emiten 'product-search:selected' con detail = product
  document.addEventListener("product-search:selected", (ev) => {
    const product = ev.detail;
    if (!product) return;
    addProductToPO(product);
  });
});


function buildBlankPurchaseOrderItemRow(index) {
  const tr = createElementWithClasses("tr", ["purchase-item-row"]);

  // --- Product ID and name ---
  const productCell = document.createElement("td");
  const hiddenInput = createElementWithClasses("input", ["item-product-id"]);
  hiddenInput.type = "hidden";
  hiddenInput.name = `purchase_order[purchase_order_items_attributes][${index}][product_id]`;

  const productName = createElementWithClasses("span", ["item-product-name", "text-muted", "small"], { text: "—" });

  productCell.append(hiddenInput, productName);
  tr.appendChild(productCell);

  // --- Quantity ---
  tr.appendChild(buildInputTd("quantity", index, {
    classes: ["form-control", "form-control-sm", "item-qty"],
    type: "number", step: 1, value: 1, min: 1
  }));

  // --- Unit Cost ---
  tr.appendChild(buildInputTd("unit_cost", index, {
    classes: ["form-control", "form-control-sm", "item-unit-cost"],
    type: "number", step: 0.01
  }));

  // --- Line Volume ---
  tr.appendChild(buildInputTd("total_line_volume", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-volume"],
    type: "text", readonly: true
  }));

  // --- Line Weight ---
  tr.appendChild(buildInputTd("total_line_weight", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-weight"],
    type: "text", readonly: true
  }));
  // --- Unit Additional Cost ---
  tr.appendChild(buildInputTd("unit_additional_cost", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-unit-additional-cost"],
    type: "number", readonly: true
  }));

  // --- Unit Compose Cost ---
  tr.appendChild(buildInputTd("unit_compose_cost", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-unit-compose-cost"],
    type: "text", readonly: true
  }));

  // --- Unit Compose Cost in MXN ---
  tr.appendChild(buildInputTd("unit_compose_cost_in_mxn", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-unit-compose-cost-mxn"],
    type: "text", readonly: true
  }));

  // --- Total Line Cost ---
  tr.appendChild(buildInputTd("total_line_cost", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-total-cost"],
    type: "text", readonly: true
  }));

  // --- Line Total Cost in MXN ---
  tr.appendChild(buildInputTd("total_line_cost_in_mxn", index, {
    classes: ["form-control-plaintext", "form-control-sm", "item-line-total-cost-mxn"],
    type: "text", readonly: true
  }));

  // --- Remove Button ---
  const actionTd = document.createElement("td");
  const removeBtn = createElementWithClasses("button", ["btn", "btn-sm", "btn-outline-danger", "remove-item"]);
  removeBtn.type = "button";
  removeBtn.innerHTML = `<i class="fa fa-trash"></i>`;
  actionTd.appendChild(removeBtn);
  tr.appendChild(actionTd);

  return tr;
}

function buildInputTd(field, index, options = {}) {
  const td = document.createElement("td");
  const input = document.createElement("input");

  if (field) {
    input.name = `purchase_order[purchase_order_items_attributes][${index}][${field}]`;
  }

  input.classList.add(...(options.classes || []));
  input.type = options.type || "text";
  if (options.step) input.step = options.step;
  if (options.value !== undefined) input.value = options.value;
  if (options.min !== undefined) input.min = options.min;
  if (options.readonly) input.readOnly = true;

  td.appendChild(input);
  return td;
}

// Calculate totals (subtotal, weight, volume, and extended line costs)
function updateItemTotals(fromTotals = false) {
  let totalLinesVolume = 0;
  let totalLinesWeight = 0;
  const shippingCost = numField("shipping_cost");
  const taxCost = numField("tax_cost");
  const otherCost = numField("other_cost");
  const exchangeRate = numField("exchange_rate") || 1;
  const totalVolume = parseFloat(document.querySelector("#total_volume")?.value) || 0;


  // First, calculate total volume for all items to use for volume unit cost calculation
  document.querySelectorAll(".purchase-item-row").forEach(row => {
    const destroyInput = row.querySelector("input.item-destroy-flag");
    if (destroyInput?.value === "1") return;

    const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
    const unitVolume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
    const unitWeight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;

    totalLinesVolume += qty * unitVolume;
    totalLinesWeight += qty * unitWeight;
  });

  const totalAdditionalCost = shippingCost + taxCost + otherCost;


  // Now calculate line totals and accumulate subtotal.
  // ✅ CORRECCIÓN: Subtotal = suma PURA de productos (qty * unit_cost), SIN extras
  // Los extras se suman después en total_order_cost
  let subtotal = 0; // suma qty * unit_cost (SOLO costo base de productos)
  let itemCount = 0; // contador de líneas activas
  let totalQty = 0; // suma de todas las cantidades

  document.querySelectorAll(".purchase-item-row").forEach(row => {
    const destroyInput = row.querySelector("input.item-destroy-flag");
    if (destroyInput?.value === "1") return;

    itemCount++; // contar línea activa

    const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
    const unitVolume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
    const unitWeight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;
    const unitCost = parseFloat(row.querySelector(".item-unit-cost")?.value) || 0;

    totalQty += qty; // acumular cantidad total

    const lineVolume = qty * unitVolume;
    // Distribución correcta: costo adicional proporcional al VOLUMEN TOTAL DE LA LÍNEA
    const volumeRate = totalLinesVolume > 0 ? (lineVolume / totalLinesVolume) : 0;
    // unitAdditionalCost se define por unidad: dividir la porción de costo de la línea entre qty (si qty>0)
    const lineAdditionalCostPortion = totalAdditionalCost * volumeRate;
    const unitAdditionalCost = qty > 0 ? (lineAdditionalCostPortion / qty) : 0;
    const unitComposeCost = unitAdditionalCost + unitCost;
    const unitComposeCostMXN = unitComposeCost * exchangeRate;
    const lineTotal = qty * unitComposeCost;
    const lineTotalMXN = lineTotal * exchangeRate;

    // ✅ Línea base sin extras (para mostrar desglose)
    const lineBaseCost = qty * unitCost;

    // Update line fields
    const unitAdditionalCostField = row.querySelector(".item-unit-additional-cost");
    if (unitAdditionalCostField) unitAdditionalCostField.value = unitAdditionalCost.toFixed(2);

    const totalField = row.querySelector(".item-total-cost");
    if (totalField) totalField.value = lineTotal.toFixed(2);

    const lineTotalMxnField = row.querySelector(".item-line-total-cost-mxn");
    if (lineTotalMxnField) lineTotalMxnField.value = lineTotalMXN.toFixed(2);

    const unitComposeCostField = row.querySelector(".item-unit-compose-cost");
    if (unitComposeCostField) unitComposeCostField.value = unitComposeCost.toFixed(2);

    const unitComposeCostMxnField = row.querySelector(".item-unit-compose-cost-mxn");
    if (unitComposeCostMxnField) unitComposeCostMxnField.value = unitComposeCostMXN.toFixed(2);

    // ✅ Acumular solo costo base en subtotal (sin extras)
    subtotal += lineBaseCost;
  });

  // Update summary fields
  const subtotalField = fieldByName("subtotal");
  if (subtotalField) {
    subtotalField.value = subtotal.toFixed(2);
    subtotalField.dataset.baseSubtotal = subtotal.toFixed(2);
  }

  // ✅ Actualizar también el display visual
  const displaySubtotal = document.getElementById("display-subtotal");
  if (displaySubtotal) displaySubtotal.textContent = `$${subtotal.toFixed(2)}`;

  const summarySubtotal = document.getElementById("summary-subtotal");
  if (summarySubtotal) summarySubtotal.textContent = `$${subtotal.toFixed(2)}`;

  // ✅ Actualizar contador de items y cantidad total en sidebar
  const summaryItemsCount = document.getElementById("summary-items-count");
  if (summaryItemsCount) summaryItemsCount.textContent = itemCount;

  const summaryTotalQty = document.getElementById("summary-total-qty");
  if (summaryTotalQty) summaryTotalQty.textContent = totalQty;

  const volumeField = fieldByName("total_volume");
  if (volumeField) volumeField.value = totalLinesVolume.toFixed(2);

  // ✅ Actualizar display de volumen
  const displayVolume = document.getElementById("display-volume");
  if (displayVolume) displayVolume.textContent = totalLinesVolume.toFixed(2);

  const weightField = fieldByName("total_weight");
  if (weightField) weightField.value = totalLinesWeight.toFixed(2);

  // ✅ Actualizar display de peso
  const displayWeight = document.getElementById("display-weight");
  if (displayWeight) displayWeight.textContent = totalLinesWeight.toFixed(2);

  // ✅ Only call updateTotals if we are NOT already coming from updateTotals
  if (!fromTotals) {
    updateTotals();
  }

}

// ✅ Update a single row's total fields
function updateLineTotals(row) {
  const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
  const unitCost = parseFloat(row.querySelector(".item-unit-cost")?.value) || 0;
  const unitVolume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
  const unitWeight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;

  const totalVolume = qty * unitVolume;
  const totalWeight = qty * unitWeight;
  const lineBaseCost = qty * unitCost; // antes era .item-total (clase inexistente)

  // Actualiza campos de volumen y peso por línea
  const volumeField = row.querySelector(".item-volume");
  if (volumeField) volumeField.value = totalVolume.toFixed(2);
  const weightField = row.querySelector(".item-weight");
  if (weightField) weightField.value = totalWeight.toFixed(2);

  // Campo de costo total base (sin adicionales): usamos .item-total-cost que sí existe
  const totalCostField = row.querySelector(".item-total-cost");
  if (totalCostField) totalCostField.value = lineBaseCost.toFixed(2);
}

// ✅ Event listeners - registrar una sola vez con event delegation
let itemListenersRegistered = false;

if (!itemListenersRegistered) {
  // Event listeners for item quantity and unit cost changes
  document.addEventListener("input", (e) => {
    if (e.target.matches(".item-qty, .item-unit-cost")) {
      const row = e.target.closest(".purchase-item-row");
      if (row) {
        updateLineTotals(row);
        updateItemTotals();
      }
    }
  });

  // Event listener for remove button click
  document.addEventListener("click", (e) => {
    if (e.target.matches(".remove-item, .remove-item *")) {
      const row = e.target.closest(".purchase-item-row");
      if (row) {
        removeItemRow(row);
      }
    }
  });

  itemListenersRegistered = true;
}

// Update totals for the entire order
function updateTotals() {
  const subtotal = numField("subtotal");
  const shipping = numField("shipping_cost");
  const tax = numField("tax_cost");
  const other = numField("other_cost");
  const exchangeRate = numField("exchange_rate");

  const total = subtotal + shipping + tax + other;
  const totalMXN = exchangeRate ? (total * exchangeRate) : 0;

  const totalCostInput = fieldByName("total_order_cost");
  const totalMXNInput = fieldByName("total_cost_mxn");

  if (totalCostInput) totalCostInput.value = total.toFixed(2);
  if (totalMXNInput) totalMXNInput.value = exchangeRate ? totalMXN.toFixed(2) : "";

  // ✅ Actualizar displays visuales
  const displayTotal = document.getElementById("display-total");
  if (displayTotal) displayTotal.textContent = `$${total.toFixed(2)}`;

  const summaryTotal = document.getElementById("summary-total");
  if (summaryTotal) summaryTotal.textContent = `$${total.toFixed(2)}`;

  const displayTotalMxn = document.getElementById("display-total-mxn");
  if (displayTotalMxn) displayTotalMxn.textContent = `$${totalMXN.toFixed(2)}`;

  const summaryTotalMxn = document.getElementById("summary-total-mxn");
  if (summaryTotalMxn) summaryTotalMxn.textContent = `$${totalMXN.toFixed(2)}`;

  // ✅ Actualizar extras en sidebar
  const summaryShipping = document.getElementById("summary-shipping");
  if (summaryShipping) summaryShipping.textContent = `$${shipping.toFixed(2)}`;

  const summaryTax = document.getElementById("summary-tax");
  if (summaryTax) summaryTax.textContent = `$${tax.toFixed(2)}`;

  const summaryOther = document.getElementById("summary-other");
  if (summaryOther) summaryOther.textContent = `$${other.toFixed(2)}`;

  updateItemTotals(true); // evita loop
}

// Reattach listeners
document.addEventListener("turbo:load", function () {
  const inputs = [
    fieldByName("subtotal"),
    fieldByName("shipping_cost"),
    fieldByName("tax_cost"),
    fieldByName("other_cost"),
    fieldByName("exchange_rate")
  ];
  inputs.forEach(input => input?.addEventListener("input", updateTotals));

  // Actualizar etiqueta de tipo de cambio al cambiar moneda
  const currencySelect = fieldByName("currency");
  const exchangeLeftLabel = document.getElementById("exchange-rate-left-label");
  const updateExchangeLabel = () => {
    if (!exchangeLeftLabel || !currencySelect) return;
    const cur = currencySelect.value || (currencySelect.options[currencySelect.selectedIndex]?.text) || "USD";
    exchangeLeftLabel.textContent = `1 ${cur} =`;
  };
  currencySelect?.addEventListener("change", updateExchangeLabel);
  updateExchangeLabel();
  updateTotals();
});

function removeItemRow(row) {
  const destroyField = row.querySelector(".item-destroy-flag");

  if (destroyField) {
    // This row represents a saved record; mark it for deletion
    destroyField.value = "1";
    row.style.display = "none"; // hide it visually
  } else {
    // This is a new unsaved row; remove from DOM
    row.remove();
  }

  updateItemTotals();
  updateTotals();
}