document.addEventListener("turbo:load", () => {
  const searchInput = document.querySelector("#product-search-sale");
  const resultsContainer = document.querySelector("#product-search-results-sale");

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
  const resultsBox = document.querySelector("#product-search-results-sale");
  const tbody = document.querySelector("#sale-order-items-table tbody");
  let index = tbody?.children.length || 0;

  if (!resultsBox || !tbody) return;

  // Handle product selection
  resultsBox.addEventListener("click", (e) => {
    const item = e.target.closest(".list-group-item");
    if (!item) return;

    const product = JSON.parse(item.dataset.product);
    const row = buildBlankPurchaseOrderItemRow(index);

    // Fill in product details
    row.querySelector(".item-product-id").value = product.id;
    row.querySelector(".item-product-name").textContent = product.product_name;
    row.querySelector(".item-qty").value = 1;
    row.querySelector(".item-unit-cost").value = 0;

    // Fill volume and weight fields
    const volume = product.length_cm * product.width_cm * product.height_cm;

    const volumeField = row.querySelector(".item-volume");
    volumeField.value = volume;
    volumeField.dataset.unitVolume = volume;

    const weightField = row.querySelector(".item-weight");
    weightField.value = product.weight_gr;
    weightField.dataset.unitWeight = product.weight_gr;

      // ✅ Remove placeholder row
    const placeholderRow = document.querySelector("#purchase-without-items");
    if (placeholderRow) placeholderRow.remove();

    tbody.appendChild(row);
    index++;

    // Clear search
    document.querySelector("#product-search").value = "";
    resultsBox.innerHTML = "";

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

// TODO: Add event listener to remove button

