// app/javascript/custom/hide_modal.js
document.addEventListener("turbo:submit-end", (e) => {
  if (e.detail.success) {
    document.getElementById("shipment_modal").innerHTML = "";
  }
});