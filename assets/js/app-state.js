/* ALBASHIR app-state.js v1.0 — UI-only state. Connectivity pill + direction. No backend calls. */
(function () {
  function renderStatus() {
    var els = document.querySelectorAll("[data-alb-status]");
    els.forEach(function (el) {
      var on = navigator.onLine;
      el.className = "alb-badge " + (on ? "ONLINE" : "OFFLINE");
      el.textContent = on ? "SYSTEM ONLINE" : "OFFLINE";
    });
  }
  window.addEventListener("online", renderStatus);
  window.addEventListener("offline", renderStatus);
  document.addEventListener("DOMContentLoaded", renderStatus);
})();
