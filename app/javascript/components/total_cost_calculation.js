document.addEventListener("turbo:load", function () {
  const subtotalInput = document.querySelector("#purchase_order_subtotal");
  const shippingInput = document.querySelector("#purchase_order_shipping_cost");
  const taxInput = document.querySelector("#purchase_order_tax_cost");
  const otherInput = document.querySelector("#purchase_order_other_cost");
  const exchangeInput = document.querySelector("#purchase_order_exchange_rate");

  const totalCostInput = document.querySelector("#total_order_cost");
  const totalMXNInput = document.querySelector("#total_cost_mxn");

  if (!subtotalInput || !shippingInput || !taxInput || !otherInput || !exchangeInput) {
    return;
  }

  function updateTotals() {
    const subtotal = parseFloat(subtotalInput?.value) || 0;
    const shipping = parseFloat(shippingInput?.value) || 0;
    const tax = parseFloat(taxInput?.value) || 0;
    const other = parseFloat(otherInput?.value) || 0;
    const exchangeRate = parseFloat(exchangeInput?.value) || 0;

    const total = subtotal + shipping + tax + other;
    totalCostInput.value = total.toFixed(2);

    const totalMXN = total * exchangeRate;
    totalMXNInput.value = exchangeRate ? totalMXN.toFixed(2) : "";
  }

  [subtotalInput, shippingInput, taxInput, otherInput, exchangeInput].forEach(input => {
    input?.addEventListener("input", updateTotals);
  });

  updateTotals(); // initial run
});