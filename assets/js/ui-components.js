/* ALBASHIR ui-components.js v1.0 — display helpers only. No Supabase, no QR, no auth decisions. */
(function (w) {
  function badge(state) {
    var s = String(state || "").toUpperCase();
    return '<span class="alb-badge ' + s + '">' + s + "</span>";
  }
  function alertBox(kind, msg) {
    return '<div class="alb-alert ' + kind + '">' + msg + "</div>";
  }
  function openModal(id) { var m = document.getElementById(id); if (m) m.classList.add("open"); }
  function closeModal(id) { var m = document.getElementById(id); if (m) m.classList.remove("open"); }
  function markInvalid(fieldId, on) {
    var f = document.getElementById(fieldId);
    if (f && f.closest) f.closest(".alb-field").classList.toggle("invalid", !!on);
  }
  function bindFileName(inputId, labelId) {
    var i = document.getElementById(inputId), l = document.getElementById(labelId);
    if (i && l) i.addEventListener("change", function () { l.textContent = (i.files && i.files[0] && i.files[0].name) || ""; });
  }
  w.ALBASHIR_UI = { badge: badge, alertBox: alertBox, openModal: openModal, closeModal: closeModal, markInvalid: markInvalid, bindFileName: bindFileName };
})(window);
