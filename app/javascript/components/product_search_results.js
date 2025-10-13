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
            resultsContainer.appendChild(item);
          });
        });
    }, 300); // debounce
  });
});