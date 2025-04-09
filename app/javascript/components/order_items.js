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
  const tbody = document.querySelector("#order-items-table tbody");
  let index = tbody?.children.length || 0;

  if (!resultsBox || !tbody) return;

  // Handle product selection
  resultsBox.addEventListener("click", (e) => {
    const item = e.target.closest(".list-group-item");
    if (!item) return;

    // Check the context
    const contextElement = document.querySelector(".order-context");
    const context = contextElement?.dataset?.context || "default";

    const product = JSON.parse(item.dataset.product);
    const row = buildBlankPurchaseOrderItemRow(index);

    // Fill in product details
    row.querySelector(".item-product-id").value = product.id;
    row.querySelector(".item-product-name").textContent = product.product_name;
    row.querySelector(".item-qty").value = 1;
    row.querySelector(".item-unit-cost").value = 0;

    if (context === "sale-order") {
      row.querySelector(".item-unit-discount").value = 0;
      row.querySelector(".item-unit-final-price").value = 0;
    }

    // Fill volume and weight fields
    const volume = product.length_cm * product.width_cm * product.height_cm;

    const volumeField = row.querySelector(".item-volume");
    volumeField.value = volume;
    volumeField.dataset.unitVolume = volume;

    const weightField = row.querySelector(".item-weight");
    weightField.value = product.weight_gr;
    weightField.dataset.unitWeight = product.weight_gr;

      // ✅ Remove placeholder row
    const placeholderRow = document.querySelector(".order-without-items");
    if (placeholderRow) placeholderRow.remove();

    tbody.appendChild(row);
    index++;

    // Clear search
    document.querySelector("#product-search").value = "";
    resultsBox.innerHTML = "";

    // Trigger update of totals
    updateItemTotals();
  });
});

function buildBlankPurchaseOrderItemRow(index) {
  const tr = createElementWithClasses("tr", ["item-row"]);
  const contextElement = document.querySelector(".order-context");
  const context = contextElement.dataset.context || "default";
  const contextText = context === "purchase-order" ? "purchase" : "sale";

  // --- Product ID and name ---
  const productCell = document.createElement("td");
  const hiddenInput = createElementWithClasses("input", ["item-product-id"]);
  hiddenInput.type = "hidden";
  hiddenInput.name = `${contextText}_order[${contextText}_order_items_attributes][${index}][product_id]`;

  const productName = createElementWithClasses("span", ["item-product-name", "text-muted", "small"], { text: "—" });

  productCell.append(hiddenInput, productName);
  tr.appendChild(productCell);

  // TODO: Need to fix the sales order save
  // --- Quantity ---
  tr.appendChild(buildInputTd("quantity", index, context, {
    classes: ["form-control", "form-control-sm", "item-qty"],
    type: "number", step: 1, value: 1, min: 1
  }));

  // --- Unit Cost ---
  tr.appendChild(buildInputTd("unit_cost", index, context, {
    classes: ["form-control", "form-control-sm", "item-unit-cost"],
    type: "number", step: 0.01
  }));
  if (context === "sale-order") {
    // --- Unit Discount ---
    tr.appendChild(buildInputTd("unit_discount", index, context, {
      classes: ["form-control", "form-control-sm", "item-unit-discount"],
      type: "number", step: 0.01
    }));

    // --- Unit final Price ---
    tr.appendChild(buildInputTd("unit_final_price", index, context, {
      classes: ["form-control", "form-control-sm", "item-unit-final-price", "form-control-plaintext"],
      type: "number", step: 0.01, readonly: true
    }));

        // --- Line Volume ---
    tr.appendChild(buildInputTd("total_line_volume", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-volume"],
      type: "text", readonly: true
    }));

    // --- Line Weight ---
    tr.appendChild(buildInputTd("total_line_weight", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-weight"],
      type: "text", readonly: true
    }));

    // --- Total Line Cost ---
    tr.appendChild(buildInputTd("total_line_cost", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-total-line-cost"],
      type: "text", readonly: true
    }));
  }



  if (context === "purchase-order") {
        // --- Line Volume ---
    tr.appendChild(buildInputTd("total_line_volume", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-volume"],
      type: "text", readonly: true
    }));

    // --- Line Weight ---
    tr.appendChild(buildInputTd("total_line_weight", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-weight"],
      type: "text", readonly: true
    }));

    // --- Unit Additional Cost ---
    tr.appendChild(buildInputTd("unit_additional_cost", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-unit-additional-cost"],
      type: "number", readonly: true
    }));

    // --- Unit Compose Cost ---
    tr.appendChild(buildInputTd("unit_compose_cost", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-unit-compose-cost"],
      type: "text", readonly: true
    }));

    // --- Unit Compose Cost in MXN ---
    tr.appendChild(buildInputTd("unit_compose_cost_in_mxn", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-unit-compose-cost-mxn"],
      type: "text", readonly: true
    }));

    // --- Total Line Cost ---
    tr.appendChild(buildInputTd("total_line_cost", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-total-cost"],
      type: "text", readonly: true
    }));

      // --- Line Total Cost in MXN ---
    tr.appendChild(buildInputTd("total_line_cost_in_mxn", index, context, {
      classes: ["form-control-plaintext", "form-control-sm", "item-line-total-cost-mxn"],
      type: "text", readonly: true
    }));
  }



  // --- Remove Button ---
  const actionTd = document.createElement("td");
  const removeBtn = createElementWithClasses("button", ["btn", "btn-sm", "btn-outline-danger", "remove-item"]);
  removeBtn.type = "button";
  removeBtn.innerHTML = `<i class="fa fa-trash"></i>`;
  actionTd.appendChild(removeBtn);
  tr.appendChild(actionTd);

  return tr;
}

function buildInputTd(field, index, context, options = {}) {
  const td = document.createElement("td");
  const input = document.createElement("input");
  const contextText = context === "purchase-order" ? "purchase" : "sale";
  if (field) {
    input.name = `${contextText}_order[${contextText}_order_items_attributes][${index}][${field}]`;
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
  let subtotal = 0;
  let totalLinesVolume = 0;
  let totalLinesWeight = 0;
  const shippingCost = parseFloat(document.querySelector("#order_shipping_cost")?.value) || 0;
  const taxCost = parseFloat(document.querySelector("#order_tax_cost")?.value) || 0;
  const otherCost = parseFloat(document.querySelector("#order_other_cost")?.value) || 0;
  const exchangeRate = parseFloat(document.querySelector("#order_exchange_rate")?.value) || 1;
  const totalVolume = parseFloat(document.querySelector("#total_volume")?.value) || 0;


  // First, calculate total volume for all items to use for volume unit cost calculation
  document.querySelectorAll(".item-row").forEach(row => {
    const destroyInput = row.querySelector("input.item-destroy-flag");
    if (destroyInput?.value === "1") return;

    const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
    const unitVolume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
    const unitWeight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;

    totalLinesVolume += qty * unitVolume;
    totalLinesWeight += qty * unitWeight;
  });

  const totalAdditionalCost = shippingCost + taxCost + otherCost;

  // Get context
  const contextElement = document.querySelector(".order-context");
  const context = contextElement?.dataset?.context || "default";


  // Now calculate line totals and accumulate subtotal
  document.querySelectorAll(".item-row").forEach(row => {
    const destroyInput = row.querySelector("input.item-destroy-flag");
    if (destroyInput?.value === "1") return;

    const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
    const unitVolume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
    const unitWeight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;
    const unitCost = parseFloat(row.querySelector(".item-unit-cost")?.value) || 0;


    const lineVolume = qty * unitVolume;
    const volumeRate = totalLinesVolume > 0 ? (lineVolume / qty) / totalLinesVolume : 0;
    const unitAdditionalCost = totalAdditionalCost * volumeRate;
    const unitComposeCost = unitAdditionalCost + unitCost;
    const unitComposeCostMXN = unitComposeCost * exchangeRate;
    let lineTotal = qty * unitComposeCost;
    const lineTotalMXN = lineTotal * exchangeRate;

    if (context === "sale-order") {
      const unitDiscount = parseFloat(row.querySelector(".item-unit-discount")?.value) || 0;
      const unitFinalPrice = unitCost - unitDiscount;
      const unitFinalPriceField = row.querySelector(".item-unit-final-price");
      if (unitFinalPriceField) unitFinalPriceField.value = unitFinalPrice.toFixed(2);
      lineTotal = qty * unitFinalPrice;
      const totalLineCostField = row.querySelector(".item-total-line-cost");

      if (totalLineCostField) totalLineCostField.value = lineTotal.toFixed(2);

      subtotal += qty * unitFinalPrice;
    } else {
      const unitDiscount = parseFloat(row.querySelector(".item-unit-discount")?.value) || 0;
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

      subtotal += qty * unitCost;
    }




  });

  // Update summary fields
  const subtotalField = document.querySelector("#order_subtotal");
  if (subtotalField) subtotalField.value = subtotal.toFixed(2);

  const volumeField = document.querySelector("#total_volume");
  if (volumeField) volumeField.value = totalLinesVolume.toFixed(2);

  const weightField = document.querySelector("#total_weight");
  if (weightField) weightField.value = totalLinesWeight.toFixed(2);

  // ✅ Only call updateTotals if we are NOT already coming from updateTotals
  if (!fromTotals) {
    updateTotals();
  }

}

// ✅ Update a single row's total fields
function updateLineTotals(row) {
  const qty = parseFloat(row.querySelector(".item-qty")?.value) || 0;
  const unitCost = parseFloat(row.querySelector(".item-unit-cost")?.value) || 0;
  const volume = parseFloat(row.querySelector(".item-volume")?.dataset?.unitVolume) || 0;
  const weight = parseFloat(row.querySelector(".item-weight")?.dataset?.unitWeight) || 0;
  const unitDiscount = parseFloat(row.querySelector(".item-unit-discount")?.value) || 0;
  const unitFinalPrice = unitCost - unitDiscount;

  const totalCost = qty * unitCost;
  const totalVolume = qty * volume;
  const totalWeight = qty * weight;
  const totalLineCost = qty * unitFinalPrice;

  const unitFinalPriceField = row.querySelector(".item-unit-final-price");
  if (unitFinalPriceField) unitFinalPriceField.value = unitFinalPrice.toFixed(2);

  const totalLineCostField = row.querySelector(".item-total-line-cost");
  if (totalLineCostField) totalLineCostField.value = totalLineCost.toFixed(2);

  const totalField = row.querySelector(".item-total");
  if (totalField) totalField.value = totalCost.toFixed(2);

  const volumeField = row.querySelector(".item-volume");
  if (volumeField) volumeField.value = totalVolume.toFixed(2);

  const weightField = row.querySelector(".item-weight");
  if (weightField) weightField.value = totalWeight.toFixed(2);
}

// Event listeners for item quantity and unit cost changes
document.addEventListener("input", (e) => {
  if (e.target.matches(".item-qty, .item-unit-cost")) {
    const row = e.target.closest(".item-row");
    if (row) {
      updateLineTotals(row);
      updateItemTotals();
    }
  }
});
// Event listener for remove button click
document.addEventListener("click", (e) => {
  if (e.target.matches(".remove-item, .remove-item *")) {
    const row = e.target.closest(".item-row");
    if (row) {
      removeItemRow(row);
    }
  }
});

// Update totals for the entire order
function updateTotals() {
  const contextElement = document.querySelector(".order-context");
  const context = contextElement?.dataset?.context || "default";

  const subtotal = parseFloat(document.querySelector("#order_subtotal")?.value) || 0;
  let total = 0
  if(context === "sale-order") {
    // FIX: The cost are not being updated.
    const taxRate = document.querySelector("#sale_order_tax_rate");
    const taxTotal = document.querySelector("#sale_order_total_tax");

    if (taxRate && taxTotal) {
      const taxRateValue = parseFloat(taxRate.value) || 0;
      const taxTotalValue = subtotal * (taxRateValue);
      taxTotal.value = taxTotalValue.toFixed(2);

      total = subtotal + taxTotalValue;
      const totalOrderValueInput = document.querySelector("#sale_order_total_order_value");
      if (totalOrderValueInput) totalOrderValueInput.value = total.toFixed(2);
    }

  } else {
    const other = parseFloat(document.querySelector("#order_other_cost")?.value) || 0;
    const exchangeRate = parseFloat(document.querySelector("#order_exchange_rate")?.value) || 0;
    const shipping = parseFloat(document.querySelector("#order_shipping_cost")?.value) || 0;
    const tax = parseFloat(document.querySelector("#order_tax_cost")?.value) || 0;
    total = subtotal + shipping + tax + other;
    const totalMXN = total * exchangeRate;
    const totalCostInput = document.querySelector("#total_order_cost");
    const totalMXNInput = document.querySelector("#total_cost_mxn");
    if (totalCostInput) totalCostInput.value = total.toFixed(2);
    if (totalMXNInput) totalMXNInput.value = exchangeRate ? totalMXN.toFixed(2) : "";
  }

  // ✅ Safely update items first (but prevent infinite loop)
  updateItemTotals(true);
}

// Reattach listeners
document.addEventListener("turbo:load", function () {
  const subtotalInput = document.querySelector("#order_subtotal");
  const shippingInput = document.querySelector("#order_shipping_cost");
  const taxInput = document.querySelector("#order_tax_cost");
  const otherInput = document.querySelector("#order_other_cost");
  const exchangeInput = document.querySelector("#order_exchange_rate");
  const taxRate = document.querySelector("#sale_order_tax_rate");

  [subtotalInput, shippingInput, taxInput, otherInput, exchangeInput, taxRate].forEach(input => {
    input?.addEventListener("input", updateTotals);
  });

  updateTotals(); // initial run
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
