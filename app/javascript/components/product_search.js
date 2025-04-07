function buildProductSearchItem(product) {
  const item = document.createElement("button");
  item.className = "list-group-item list-group-item-action";
  item.innerHTML = `
    <div class="d-flex align-items-center">
      <img src="${product.thumbnail_url}" alt="${product.product_name}" class="me-2 rounded" style="width: 40px; height: 40px;">
      <div>
        <strong>${product.product_name}</strong><br>
        <small class="text-muted">SKU: ${product.product_sku}</small>
      </div>
    </div>
  `;

  // ✅ Disparar evento personalizado
  item.addEventListener("click", () => {
    const event = new CustomEvent("product:selected", { detail: product });
    document.dispatchEvent(event);
  });

  return item;
}
