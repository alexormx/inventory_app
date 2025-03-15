
document.addEventListener("turbo:render", function() {
  let flash = document.querySelector(".flash-message");
  if(!flash) return;
  setTimeout(() => {
    flash.classList.remove("show");
    flash.classList.add("fade");
    setTimeout(() => flash.remove(), 500); // ✅ Removes the message after fading
  }, 5000); // ✅ Fades out after 5 seconds
});
