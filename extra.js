/* dragonfarm site behaviour: copy buttons, scroll reveal, and the animated
   six-step pipeline on the home page (drawn with D3, see df-pipeline.js). */
(function () {
  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }
  function load(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement("script");
      s.src = src; s.onload = resolve; s.onerror = reject;
      document.head.appendChild(s);
    });
  }
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  ready(function () {
    document.querySelectorAll("[data-copy]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var text = btn.getAttribute("data-copy"), old = btn.textContent;
        var done = function () { btn.textContent = "Copied"; setTimeout(function () { btn.textContent = old; }, 1400); };
        if (navigator.clipboard) navigator.clipboard.writeText(text).then(done);
        else done();
      });
    });

    var reveals = document.querySelectorAll(".df-reveal");
    if (reveals.length) {
      if ("IntersectionObserver" in window && !reduce) {
        var io = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
        }, { threshold: 0.12 });
        reveals.forEach(function (el) { io.observe(el); });
      } else {
        reveals.forEach(function (el) { el.classList.add("in"); });
      }
    }

    if (!document.getElementById("df-stepper")) return;
    load("vendor/d3.v7.min.js").then(function () { return load("df-pipeline.js"); }).then(initStepper);
  });

  function initStepper() {
    var d3 = window.d3, P = window.DragonPipeline;
    var svg = d3.select("#df-stepper");
    var shots = Array.prototype.slice.call(document.querySelectorAll(".df-shots img"));
    var cap = document.getElementById("df-cap");
    var captions = [
      "Feed it PDFs, Word files, web pages, or spreadsheets. It reads everything and forgets nothing.",
      "Ask it anything. It answers in full from what it read, and admits when the documents are silent.",
      "It writes its own practice questions. You keep the good ones and toss the rest.",
      "Pick a dragon size, set a few numbers, press Start training.",
      "Watch it learn. The line going down is the good kind of trouble.",
      "Put the trained dragon next to the wild one, both answering from your documents.",
    ];
    var narrow = window.innerWidth < 640;
    var opts = narrow
      ? { width: 540, height: 118, showSub: false, padX: 34, labelSize: 17 }
      : { width: 1000, height: 156, showSub: true };
    var cur = 0, idx = 0, timer = null, resumeTimer = null;

    // The stepper sits on the hero, which is light in light mode; redraw it
    // with matching colours when the theme switch is used.
    var LIGHT = { bg: "#FFFFFF", check: "#1B1206", track: "#E3DED5", muted: "#8A93A8", text: "#0B1020",
                  amber: "#F08A00", coral: "#E4502A", ring: "#D5CFC4" };
    function palette() { return document.documentElement.getAttribute("data-bs-theme") === "light" ? LIGHT : {}; }
    opts.colors = palette();
    new MutationObserver(function () { opts.colors = palette(); P.render(d3, svg, cur, opts); })
      .observe(document.documentElement, { attributes: true, attributeFilter: ["data-bs-theme"] });

    P.render(d3, svg, 0, opts);
    function show(i) {
      shots.forEach(function (im, k) { im.classList.toggle("on", k === i); });
      cap.innerHTML = "<strong>Step " + (i + 1) + " of 6 · " + P.STEPS[i].name + ".</strong> " + captions[i];
    }
    function go(i, ms) {
      var from = cur;
      idx = i;
      if (reduce) { cur = i; P.render(d3, svg, i, opts); show(i); return; }
      svg.interrupt("pos");
      svg.transition("pos").duration(ms || 900).ease(d3.easeCubicInOut).tween("pos", function () {
        var it = d3.interpolateNumber(from, i);
        return function (x) { cur = it(x); P.render(d3, svg, cur, opts); };
      });
      show(i);
    }
    function start() {
      if (reduce || timer) return;
      timer = setInterval(function () { go((idx + 1) % 6, idx === 5 ? 1300 : 900); }, 3600);
    }
    function stop() { clearInterval(timer); timer = null; clearTimeout(resumeTimer); }

    svg.selectAll("g.df-node")
      .attr("tabindex", 0).attr("role", "button")
      .attr("aria-label", function (d) { return "Step " + d.n + ": " + d.name; })
      .on("click", function (ev, d) {
        stop(); go(d.n - 1);
        resumeTimer = setTimeout(start, 14000);
      })
      .on("keydown", function (ev, d) {
        if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); stop(); go(d.n - 1); resumeTimer = setTimeout(start, 14000); }
      });

    var stage = document.querySelector(".df-stage");
    stage.addEventListener("mouseenter", stop);
    stage.addEventListener("mouseleave", start);
    document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else start(); });
    show(0);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) { es[0].isIntersecting ? start() : stop(); }, { threshold: 0.25 }).observe(stage);
    } else { start(); }
  }
})();
