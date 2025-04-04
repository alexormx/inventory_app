document.addEventListener("turbo:load", () => {
  document.body.addEventListener("click", function (event) {
    if (event.target.matches(".toggle-inventory-btn")) {
      const button = event.target
      const turboFrame = button.closest("turbo-frame")
      const inventoryTable = turboFrame.querySelector(".inventory-items")

      if (inventoryTable) {
        const isHidden = inventoryTable.classList.toggle("d-none")
        button.textContent = isHidden ? "👁 View Items" : "👁 Hide Items"
      }
    }
  })
})
