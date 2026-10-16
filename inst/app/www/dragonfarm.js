// Small client-side helpers for the dragonfarm app.
(function () {
  // "1 Documents" -> a numbered step badge and a label, so the navbar reads
  // as a stepper. Titles without a leading number are left as text.
  function setTitle(link, title) {
    var m = /^(\d+)\s+(.*)$/.exec(title);
    if (!m) { link.textContent = title; return; }
    link.innerHTML = "";
    var n = document.createElement("span"); n.className = "df-step-n"; n.textContent = m[1];
    var t = document.createElement("span"); t.className = "df-step-t"; t.textContent = m[2];
    // The space keeps the accessible name "3 Train" rather than "3Train";
    // the flex layout ignores it visually.
    link.appendChild(n); link.appendChild(document.createTextNode(" ")); link.appendChild(t);
    link.setAttribute("title", m[2]);
  }

  function decorate() {
    document.querySelectorAll("#nav a[data-value]").forEach(function (link) {
      if (!link.querySelector(".df-step-n")) setTitle(link, link.textContent.trim());
    });
  }
  if (document.readyState !== "loading") decorate();
  else document.addEventListener("DOMContentLoaded", decorate);

  // Renumber navbar tabs when the route changes (documents first, or table
  // first): {value: "1 Documents", ...} keyed by each nav_panel's value.
  Shiny.addCustomMessageHandler("df-tab-titles", function (titles) {
    Object.keys(titles).forEach(function (value) {
      var link = document.querySelector('#nav a[data-value="' + value + '"]');
      if (link) setTitle(link, titles[value]);
    });
  });
})();
