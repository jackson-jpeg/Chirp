/* Hero mesh visualization.
   Nodes drift, link when they're in range, and flood packets hop-by-hop —
   each node relaying a given wave exactly once, the way MeshRouter dedupes. */
(function () {
  var cv = document.getElementById('mesh');
  if (!cv) return;

  var ctx = cv.getContext('2d');
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Colors come from brand.css (--mesh-packet, --mesh-node) so the mesh
  // follows the day/night scheme; re-read when the scheme flips.
  var AMBER = '255,201,58';
  var CREAM = '245,240,230';
  function readColors() {
    var cs = getComputedStyle(document.documentElement);
    AMBER = (cs.getPropertyValue('--mesh-packet') || AMBER).trim() || AMBER;
    CREAM = (cs.getPropertyValue('--mesh-node') || CREAM).trim() || CREAM;
  }
  readColors();
  var scheme = window.matchMedia('(prefers-color-scheme: dark)');
  var onScheme = function () { readColors(); if (reduced) draw(); };
  if (scheme.addEventListener) scheme.addEventListener('change', onScheme);
  else if (scheme.addListener) scheme.addListener(onScheme);
  var MAX_TTL = 8;          // matches MeshPacket.maxTTL
  var LINK = 200;           // px: "in range"

  var W = 0, H = 0, dpr = 1;
  var nodes = [], packets = [], wave = null, waveAt = 0, running = true;

  function rand(a, b) { return a + Math.random() * (b - a); }

  function resize() {
    var r = cv.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = r.width; H = r.height;
    cv.width = Math.round(W * dpr);
    cv.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    build();
  }

  function build() {
    var area = W * H;
    var n = Math.max(9, Math.min(30, Math.round(area / 32000)));
    nodes = [];
    for (var i = 0; i < n; i++) {
      nodes.push({
        x: rand(0, W), y: rand(0, H),
        vx: rand(-0.11, 0.11), vy: rand(-0.11, 0.11),
        r: rand(2.1, 3.4),
        flash: 0
      });
    }
    packets = [];
    wave = null;
  }

  function neighbors(i) {
    var out = [], a = nodes[i];
    for (var j = 0; j < nodes.length; j++) {
      if (j === i) continue;
      var b = nodes[j], dx = a.x - b.x, dy = a.y - b.y;
      if (dx * dx + dy * dy < LINK * LINK) out.push(j);
    }
    return out;
  }

  function emit(from, ttl) {
    var nb = neighbors(from);
    for (var k = 0; k < nb.length; k++) {
      if (wave.seen[nb[k]]) continue;              // already carried this wave
      packets.push({ a: from, b: nb[k], t: 0, ttl: ttl });
    }
  }

  function startWave() {
    if (!nodes.length) return;
    var src = Math.floor(Math.random() * nodes.length);
    wave = { seen: {} };
    wave.seen[src] = 1;
    nodes[src].flash = 1;
    emit(src, MAX_TTL);
  }

  function step(dt) {
    var i, p;

    for (i = 0; i < nodes.length; i++) {
      var nd = nodes[i];
      nd.x += nd.vx * dt; nd.y += nd.vy * dt;
      if (nd.x < 0 || nd.x > W) nd.vx *= -1;
      if (nd.y < 0 || nd.y > H) nd.vy *= -1;
      nd.x = Math.max(0, Math.min(W, nd.x));
      nd.y = Math.max(0, Math.min(H, nd.y));
      if (nd.flash > 0) nd.flash = Math.max(0, nd.flash - dt * 0.022);
    }

    for (i = packets.length - 1; i >= 0; i--) {
      p = packets[i];
      var a = nodes[p.a], b = nodes[p.b];
      if (!a || !b) { packets.splice(i, 1); continue; }
      var d = Math.hypot(b.x - a.x, b.y - a.y) || 1;
      p.t += (dt * 0.42) / d;
      if (p.t >= 1) {
        packets.splice(i, 1);
        if (wave && !wave.seen[p.b]) {           // dedupe: relay once per wave
          wave.seen[p.b] = 1;
          b.flash = 1;
          if (p.ttl > 1) emit(p.b, p.ttl - 1);
        }
      }
    }

    waveAt += dt;
    if (waveAt > 2000 && packets.length === 0) { waveAt = 0; startWave(); }
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);
    var i, j, a, b;

    // links
    for (i = 0; i < nodes.length; i++) {
      a = nodes[i];
      for (j = i + 1; j < nodes.length; j++) {
        b = nodes[j];
        var dx = a.x - b.x, dy = a.y - b.y;
        var d2 = dx * dx + dy * dy;
        if (d2 > LINK * LINK) continue;
        var f = 1 - Math.sqrt(d2) / LINK;
        ctx.strokeStyle = 'rgba(' + CREAM + ',' + (f * 0.16).toFixed(3) + ')';
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
      }
    }

    // packets in flight
    for (i = 0; i < packets.length; i++) {
      var p = packets[i];
      a = nodes[p.a]; b = nodes[p.b];
      if (!a || !b) continue;
      var x = a.x + (b.x - a.x) * p.t, y = a.y + (b.y - a.y) * p.t;
      var tx = a.x + (b.x - a.x) * Math.max(0, p.t - 0.22);
      var ty = a.y + (b.y - a.y) * Math.max(0, p.t - 0.22);
      var g = ctx.createLinearGradient(tx, ty, x, y);
      g.addColorStop(0, 'rgba(' + AMBER + ',0)');
      g.addColorStop(1, 'rgba(' + AMBER + ',0.85)');
      ctx.strokeStyle = g; ctx.lineWidth = 1.6;
      ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(x, y); ctx.stroke();

      ctx.fillStyle = 'rgba(' + AMBER + ',0.95)';
      ctx.beginPath(); ctx.arc(x, y, 2.1, 0, 6.2832); ctx.fill();
    }

    // nodes
    for (i = 0; i < nodes.length; i++) {
      var nd = nodes[i];
      if (nd.flash > 0) {
        var rr = nd.r + (1 - nd.flash) * 22;
        ctx.strokeStyle = 'rgba(' + AMBER + ',' + (nd.flash * 0.4).toFixed(3) + ')';
        ctx.lineWidth = 1.2;
        ctx.beginPath(); ctx.arc(nd.x, nd.y, rr, 0, 6.2832); ctx.stroke();
      }
      var lit = 0.26 + nd.flash * 0.7;
      ctx.fillStyle = nd.flash > 0.02
        ? 'rgba(' + AMBER + ',' + lit.toFixed(3) + ')'
        : 'rgba(' + CREAM + ',0.3)';
      ctx.beginPath(); ctx.arc(nd.x, nd.y, nd.r, 0, 6.2832); ctx.fill();
    }
  }

  var last = 0;
  function frame(ts) {
    if (!running) { last = ts; requestAnimationFrame(frame); return; }
    var dt = Math.min(48, ts - last || 16);
    last = ts;
    step(dt);
    draw();
    requestAnimationFrame(frame);
  }

  var ro = window.ResizeObserver ? new ResizeObserver(resize) : null;
  if (ro) ro.observe(cv); else window.addEventListener('resize', resize);

  resize();

  if (reduced) {
    draw();                                  // static graph, no motion
  } else {
    document.addEventListener('visibilitychange', function () {
      running = !document.hidden;
    });
    if (window.IntersectionObserver) {
      new IntersectionObserver(function (es) {
        running = es[0].isIntersecting && !document.hidden;
      }, { threshold: 0.01 }).observe(cv);
    }
    startWave();
    requestAnimationFrame(frame);
  }
})();
