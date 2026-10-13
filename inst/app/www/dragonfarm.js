// Small client-side helpers for the dragon-farm app.
(function () {
  // Renumber navbar tabs when the route changes (documents first, or table
  // first): {value: "1 Documents", ...} keyed by each nav_panel's value.
  Shiny.addCustomMessageHandler("df-tab-titles", function (titles) {
    Object.keys(titles).forEach(function (value) {
      var link = document.querySelector('#nav a[data-value="' + value + '"]');
      if (link) link.textContent = titles[value];
    });
  });
})();
