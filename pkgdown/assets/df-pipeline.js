/* dragonfarm six-step pipeline, drawn with D3.
 *
 * One drawing function shared by the website hero (animated), the demo GIF
 * and social card (static frames), and the README banner (built in Node).
 *
 *   DragonPipeline.render(d3, svgSelection, t, options)
 *
 * t is a continuous position along the pipeline: 0 means step 1 is active,
 * 1 means step 2 is active (step 1 done), 2.5 means the line is halfway
 * between steps 3 and 4, 5 means step 6 is active (steps 1 to 5 done).
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.DragonPipeline = factory();
})(typeof self !== "undefined" ? self : this, function () {
  var STEPS = [
    { n: 1, name: "Documents", sub: "Drop in files or pages" },
    { n: 2, name: "Ask", sub: "Answers with sources" },
    { n: 3, name: "Teach", sub: "Review the questions" },
    { n: 4, name: "Train", sub: "Pick a model, press start" },
    { n: 5, name: "Monitor", sub: "Watch the loss" },
    { n: 6, name: "Try it", sub: "Compare with base" },
  ];

  // Default palette, for a dark background. render() takes options.colors
  // to override any of these (the website passes a light set in light mode).
  var COLORS = {
    bg: "#0B1020",
    check: "#0B1020",
    track: "#26324D",
    muted: "#7C89A6",
    text: "#F1F5FF",
    amber: "#FFB547",
    coral: "#FF6B35",
    ring: "#3A4766",
  };

  function geometry(width, height, opts) {
    var padX = opts.padX != null ? opts.padX : Math.max(54, width * 0.07);
    var r = opts.radius != null ? opts.radius : 20;
    var y = opts.nodeY != null ? opts.nodeY : height * (opts.showSub ? 0.4 : 0.44);
    var x0 = padX, x1 = width - padX;
    var xs = STEPS.map(function (_, i) { return x0 + (i * (x1 - x0)) / (STEPS.length - 1); });
    return { x0: x0, x1: x1, xs: xs, y: y, r: r };
  }

  function stateOf(i, t) {
    var d = t - i;
    if (d >= 0.02) return { kind: "done", arrive: 1 };
    if (d > -0.02) return { kind: "active", arrive: 1 };
    if (d > -1) return { kind: "next", arrive: 1 + d };
    return { kind: "todo", arrive: 0 };
  }

  function render(d3, svg, t, options) {
    var o = options || {};
    var C = Object.assign({}, COLORS, o.colors || {});
    var W = o.width || 960, H = o.height || 150;
    var g = geometry(W, H, o);
    var fontHead = o.fontHeading || "'Space Grotesk', 'Segoe UI', system-ui, sans-serif";
    var fontBody = o.fontBody || "'Inter', 'Segoe UI', system-ui, sans-serif";
    var labelSize = o.labelSize || 17;
    var subSize = o.subSize || 13;
    t = Math.max(0, Math.min(STEPS.length - 1, t));

    svg.attr("viewBox", "0 0 " + W + " " + H).attr("width", o.fixedSize ? W : null).attr("height", o.fixedSize ? H : null);

    var defs = svg.selectAll("defs").data([0]).join("defs");
    var grad = defs.selectAll("linearGradient#dfGrad").data([0]).join("linearGradient").attr("id", "dfGrad")
      .attr("gradientUnits", "userSpaceOnUse").attr("x1", g.x0).attr("x2", g.x1).attr("y1", 0).attr("y2", 0);
    grad.selectAll("stop").data([[0, C.amber], [1, C.coral]]).join("stop")
      .attr("offset", function (d) { return d[0]; }).attr("stop-color", function (d) { return d[1]; });

    var root = svg.selectAll("g.df-root").data([0]).join("g").attr("class", "df-root");

    root.selectAll("line.df-track").data([0]).join("line").attr("class", "df-track")
      .attr("x1", g.x0).attr("x2", g.x1).attr("y1", g.y).attr("y2", g.y)
      .attr("stroke", C.track).attr("stroke-width", 4).attr("stroke-linecap", "round");

    // Glow by layering wider translucent strokes: an SVG filter renders nothing
    // on a zero-height line, and plain strokes work in every SVG renderer.
    var headX = g.x0 + (g.x1 - g.x0) * (t / (STEPS.length - 1));
    var layers = [[16, 0.10], [10, 0.16], [4, 1]];
    root.selectAll("line.df-progress").data(layers).join("line").attr("class", "df-progress")
      .attr("x1", g.x0).attr("x2", headX).attr("y1", g.y).attr("y2", g.y)
      .attr("stroke", "url(#dfGrad)").attr("stroke-linecap", "round")
      .attr("stroke-width", function (d) { return d[0]; }).attr("opacity", function (d) { return d[1]; });

    var frac = t - Math.floor(t);
    var travelling = frac > 0.03 && frac < 0.97;
    var headLayers = travelling ? [[14, 0.12], [9, 0.22], [5.5, 1]] : [];
    root.selectAll("circle.df-head").data(headLayers).join("circle").attr("class", "df-head")
      .attr("cx", headX).attr("cy", g.y).attr("r", function (d) { return d[0]; })
      .attr("fill", "#FFFFFF").attr("opacity", function (d) { return d[1]; });

    var nodes = root.selectAll("g.df-node").data(STEPS).join(function (enter) {
      var n = enter.append("g").attr("class", "df-node");
      n.append("circle").attr("class", "halo");
      n.append("circle").attr("class", "disc");
      n.append("text").attr("class", "num");
      n.append("path").attr("class", "check");
      n.append("text").attr("class", "name");
      n.append("text").attr("class", "sub");
      return n;
    });
    nodes.attr("transform", function (d, i) { return "translate(" + g.xs[i] + "," + g.y + ")"; });

    nodes.each(function (d, i) {
      var s = stateOf(i, t), node = d3.select(this);
      var amber = d3.color(C.amber), ring = d3.color(C.ring);
      var mixed = d3.interpolateRgb(C.ring, C.amber)(s.arrive);
      node.select("circle.halo").attr("r", g.r + 11)
        .attr("fill", C.amber)
        .attr("opacity", s.kind === "active" ? 0.22 : s.kind === "next" ? 0.22 * s.arrive * s.arrive : 0);
      node.select("circle.disc").attr("r", g.r)
        .attr("fill", s.kind === "done" ? "url(#dfGrad)" : C.bg)
        .attr("stroke", s.kind === "done" ? "none" : s.kind === "active" ? C.amber : s.kind === "next" ? mixed : C.ring)
        .attr("stroke-width", s.kind === "active" ? 3.5 : 2.5);
      node.select("text.num").attr("text-anchor", "middle").attr("dy", "0.35em")
        .attr("font-family", fontHead).attr("font-weight", 700).attr("font-size", 16)
        .attr("fill", s.kind === "active" ? C.amber : C.muted)
        .attr("opacity", s.kind === "done" ? 0 : 1).text(d.n);
      node.select("path.check").attr("d", "M-7.5 0.5 L-2.5 6 L8 -6")
        .attr("fill", "none").attr("stroke", C.check).attr("stroke-width", 3.4)
        .attr("stroke-linecap", "round").attr("stroke-linejoin", "round")
        .attr("opacity", s.kind === "done" ? 1 : 0);
      var lit = s.kind === "done" || s.kind === "active";
      node.select("text.name").attr("text-anchor", "middle").attr("y", g.r + 30)
        .attr("font-family", fontHead).attr("font-weight", 600).attr("font-size", labelSize)
        .attr("fill", lit ? C.text : C.muted).text(d.name);
      node.select("text.sub").attr("text-anchor", "middle").attr("y", g.r + 30 + subSize + 8)
        .attr("font-family", fontBody).attr("font-weight", 400).attr("font-size", subSize)
        .attr("fill", C.muted).attr("opacity", o.showSub ? (lit ? 1 : 0.7) : 0).text(d.sub);
    });
    return { geometry: g, t: t };
  }

  return { STEPS: STEPS, COLORS: COLORS, geometry: geometry, render: render };
});
