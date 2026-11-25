/* Round 2 core: seeded randomness, colour, the hand-drawn stroke engine,
 * organic shapes that breathe between perfect and imperfect, and the print
 * finish (paper, ink speckle, misregistration) that makes the art less
 * digital. Shared by marks.js and art.js. Canvas 2D in a unit square. */
const Core = (() => {
  'use strict';
  const TAU = Math.PI * 2;
  const BREATH = 10; // seconds per breath: six a minute, as the app's mark

  // ---------- randomness ----------
  function hash(str) {
    let h = 1779033703 ^ str.length;
    for (let i = 0; i < str.length; i++) { h = Math.imul(h ^ str.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
    h = Math.imul(h ^ (h >>> 16), 2246822507); h = Math.imul(h ^ (h >>> 13), 3266489909);
    return (h ^ (h >>> 16)) >>> 0;
  }
  function makeRng(str) {
    let a = hash(String(str));
    const next = () => {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    const r = {
      next,
      range: (lo, hi) => lo + (hi - lo) * next(),
      int: (lo, hi) => Math.floor(lo + (hi - lo + 1) * next()),
      pick: (arr) => arr[Math.floor(next() * arr.length)],
      sign: () => (next() < 0.5 ? -1 : 1),
      chance: (p) => next() < p,
      // weights: { key: weight }
      weighted: (w) => { const ks = Object.keys(w); let s = 0; for (const k of ks) s += w[k]; let x = next() * s; for (const k of ks) { x -= w[k]; if (x <= 0) return k; } return ks[ks.length - 1]; },
    };
    return r;
  }
  function noise1(rng, oct = 3) {
    const f = [], p = [], a = [];
    let tot = 0;
    for (let i = 0; i < oct; i++) { f.push(rng.range(0.8, 1.5) * Math.pow(2.13, i)); p.push(rng.range(0, TAU)); a.push(Math.pow(0.5, i)); tot += a[i]; }
    return (x) => { let s = 0; for (let i = 0; i < oct; i++) s += a[i] * Math.sin(f[i] * x + p[i]); return s / tot; };
  }

  // ---------- maths ----------
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const ss = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const easeOut = (t) => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
  const easeInOut = (t) => -(Math.cos(Math.PI * clamp(t, 0, 1)) - 1) / 2;
  const prog = (t, start, dur) => clamp((t - start) / dur, 0, 1);
  // 0 at full exhale, 1 at full inhale; starts at rest.
  const breathAt = (t, start = 0) => (t < start ? 0 : 0.5 - 0.5 * Math.cos((TAU * (t - start)) / BREATH));

  // ---------- colour ----------
  const cache = new Map();
  function rgb(c) {
    if (Array.isArray(c)) return c;
    let v = cache.get(c);
    if (!v) { const h = c.replace('#', ''); v = [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; cache.set(c, v); }
    return v;
  }
  const mix = (a, b, t) => { const x = rgb(a), y = rgb(b); return [lerp(x[0], y[0], t), lerp(x[1], y[1], t), lerp(x[2], y[2], t)]; };
  const css = (c, alpha = 1) => { const v = rgb(c); return `rgba(${v[0] | 0},${v[1] | 0},${v[2] | 0},${alpha})`; };
  const hex = (c) => '#' + rgb(c).map((x) => Math.round(x).toString(16).padStart(2, '0')).join('');
  function lum(c) {
    const v = rgb(c).map((x) => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); });
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
  }
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const darker = (a, b) => (lum(a) < lum(b) ? a : b);
  const lighter = (a, b) => (lum(a) < lum(b) ? b : a);
  // The roles every generator paints with.
  function roles(pal, over) {
    const c = { tile: pal.tile, form: pal.form, stroke: pal.stroke, accent: pal.accent, ...(over || {}) };
    c.deep = darker(c.tile, c.stroke); c.light = lighter(c.tile, c.stroke);
    c.lightPaper = lum(c.tile) > 0.35;
    return c;
  }

  // ---------- strokes ----------
  function resample(raw, n) {
    const m = raw.length, cum = new Float64Array(m);
    for (let i = 1; i < m; i++) cum[i] = cum[i - 1] + Math.hypot(raw[i][0] - raw[i - 1][0], raw[i][1] - raw[i - 1][1]);
    const L = cum[m - 1], out = [];
    let j = 0;
    for (let i = 0; i < n; i++) {
      const d = (L * i) / (n - 1);
      while (j < m - 2 && cum[j + 1] < d) j++;
      const seg = cum[j + 1] - cum[j] || 1, u = clamp((d - cum[j]) / seg, 0, 1);
      out.push([lerp(raw[j][0], raw[j + 1][0], u), lerp(raw[j][1], raw[j + 1][1], u)]);
    }
    return { pts: out, len: L };
  }
  function normals(pts, span = 1) {
    const n = pts.length, nx = new Float64Array(n), ny = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const a = pts[Math.max(i - span, 0)], b = pts[Math.min(i + span, n - 1)];
      const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy) || 1;
      nx[i] = -dy / l; ny[i] = dx / l;
    }
    return { nx, ny };
  }
  function profile(kind, s) {
    switch (kind) {
      case 'brush': return (0.66 + 0.34 * ss(0, 0.05, s)) * (1 - 0.8 * Math.pow(ss(0.4, 1, s), 1.25)) + 0.05;
      case 'grow': return (0.42 + 0.58 * ss(0, 0.5, s)) * (1 - 0.45 * ss(0.86, 1, s));
      case 'swell': return 0.5 + 0.5 * Math.pow(Math.sin(Math.PI * clamp(s * 1.04 - 0.02, 0, 1)), 0.7);
      case 'fade': return (0.8 + 0.2 * ss(0, 0.06, s)) * (1 - 0.7 * ss(0.6, 1, s));
      default: return (0.74 + 0.26 * ss(0, 0.05, s)) * (1 - 0.36 * ss(0.88, 1, s));
    }
  }
  // A centreline becomes a hand-drawn ribbon: even spacing, slow wobble,
  // pressure, optional nib, and a pen clock that slows in tight curves.
  function makeStroke(raw, o, rng) {
    const N = o.samples || 420;
    let { pts } = resample(raw, N);
    let { nx, ny } = normals(pts, 2);
    const wob = noise1(rng, 3), wf = rng.range(3, 6);
    pts = pts.map((p, i) => { const d = o.wobble * wob((i / (N - 1)) * wf); return [p[0] + nx[i] * d, p[1] + ny[i] * d]; });
    const r = resample(pts, N);
    pts = r.pts;
    ({ nx, ny } = normals(pts, 2));
    const pn = noise1(rng, 2), pf = rng.range(4, 8), nibA = rng.range(0, Math.PI);
    const x = new Float64Array(N), y = new Float64Array(N), w = new Float64Array(N), cost = new Float64Array(N);
    const ds = r.len / (N - 1);
    let prev = null;
    for (let i = 0; i < N; i++) {
      const s = i / (N - 1);
      x[i] = pts[i][0]; y[i] = pts[i][1];
      const ang = Math.atan2(-nx[i], ny[i]);
      let ww = o.width * profile(o.taper, s) * (1 + o.pressure * pn(s * pf));
      if (o.nib) ww *= 1 - o.nib + o.nib * (0.3 + 0.7 * Math.abs(Math.sin(ang - nibA)));
      w[i] = ww;
      if (i > 0) { let da = Math.abs(ang - prev); if (da > Math.PI) da = TAU - da; cost[i] = cost[i - 1] + ds + 0.014 * da; }
      prev = ang;
    }
    for (let i = 0; i < N; i++) cost[i] /= cost[N - 1];
    return { n: N, x, y, nx, ny, w, cost, len: r.len };
  }
  function drawStroke(ctx, st, p) {
    if (p <= 0) return;
    const { n, x, y, nx, ny, w, cost } = st;
    let k = n - 1, f = 0;
    if (p < 1) {
      let lo = 0, hi = n - 1;
      while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (cost[mid] <= p) lo = mid; else hi = mid; }
      k = lo; f = (p - cost[lo]) / (cost[hi] - cost[lo] || 1);
    }
    const k2 = Math.min(k + 1, n - 1);
    const ex = lerp(x[k], x[k2], f), ey = lerp(y[k], y[k2], f), ew = lerp(w[k], w[k2], f) / 2;
    const enx = lerp(nx[k], nx[k2], f), eny = lerp(ny[k], ny[k2], f);
    ctx.beginPath();
    ctx.moveTo(x[0] + nx[0] * w[0] / 2, y[0] + ny[0] * w[0] / 2);
    for (let i = 1; i <= k; i++) ctx.lineTo(x[i] + nx[i] * w[i] / 2, y[i] + ny[i] * w[i] / 2);
    ctx.lineTo(ex + enx * ew, ey + eny * ew);
    ctx.lineTo(ex - enx * ew, ey - eny * ew);
    for (let i = k; i >= 0; i--) ctx.lineTo(x[i] - nx[i] * w[i] / 2, y[i] - ny[i] * w[i] / 2);
    ctx.closePath();
    ctx.fill('nonzero');
    ctx.beginPath(); ctx.arc(x[0], y[0], w[0] / 2, 0, TAU); ctx.fill();
    ctx.beginPath(); ctx.arc(ex, ey, ew, 0, TAU); ctx.fill();
  }
  // Polyline builder for centrelines: lines, arcs and curves, densely sampled.
  function pen(x, y) {
    const pts = [[x, y]];
    const last = () => pts[pts.length - 1];
    const api = {
      pts,
      line(x2, y2, n = 40) { const [x1, y1] = last(); for (let i = 1; i <= n; i++) pts.push([lerp(x1, x2, i / n), lerp(y1, y2, i / n)]); return api; },
      quad(cx, cy, x2, y2, n = 60) { const [x1, y1] = last(); for (let i = 1; i <= n; i++) { const t = i / n, u = 1 - t; pts.push([u * u * x1 + 2 * u * t * cx + t * t * x2, u * u * y1 + 2 * u * t * cy + t * t * y2]); } return api; },
      cubic(c1x, c1y, c2x, c2y, x2, y2, n = 80) { const [x1, y1] = last(); for (let i = 1; i <= n; i++) { const t = i / n, u = 1 - t; pts.push([u * u * u * x1 + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * x2, u * u * u * y1 + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * y2]); } return api; },
      arc(cx, cy, rx, ry, a0, a1, n = 90) { for (let i = 1; i <= n; i++) { const a = lerp(a0, a1, i / n); pts.push([cx + rx * Math.cos(a), cy + ry * Math.sin(a)]); } return api; },
    };
    return api;
  }
  function jitterPts(pts, rng, amt) { const nz = noise1(rng, 2), nz2 = noise1(rng, 2); return pts.map(([x, y], i) => [x + amt * nz(i * 0.05), y + amt * nz2(i * 0.05)]); }

  // ---------- organic shapes ----------
  // A pebble: radius r(θ) = R(1 + Σ aₖ sin(kθ + φₖ)) plus a fine "cut" edge.
  // imperf 0 draws a true circle; 1 draws the full organic shape.
  function makeBlob(rng, cx, cy, R, rough = 1, cut = 0) {
    return {
      cx, cy, R, rot: rng.range(0, TAU), asp: rng.range(0.9, 1.08),
      a: [rng.range(0.03, 0.08) * rough, rng.range(0.015, 0.045) * rough, rng.range(0, 0.018) * rough],
      p: [rng.range(0, TAU), rng.range(0, TAU), rng.range(0, TAU)],
      cut, cp: [rng.range(0, TAU), rng.range(0, TAU)], ck: [rng.int(7, 10), rng.int(12, 17)],
    };
  }
  function blobPath(ctx, b, o = {}) {
    const grow = o.grow ?? 1, imp = o.imperf ?? 1, dx = o.dx || 0, dy = o.dy || 0, sx = o.sx || 1, sy = o.sy || 1;
    const asp = lerp(1, b.asp, imp), M = 128, c = Math.cos(b.rot), s = Math.sin(b.rot);
    if (!o.keep) ctx.beginPath();
    for (let i = 0; i <= M; i++) {
      const th = (i / M) * TAU;
      let r = 1;
      for (let k = 0; k < 3; k++) r += imp * b.a[k] * Math.sin((k + 2) * th + b.p[k]);
      if (b.cut) r += b.cut * (0.6 * Math.sin(b.ck[0] * th + b.cp[0]) + 0.4 * Math.sin(b.ck[1] * th + b.cp[1]));
      r *= b.R * grow;
      const ux = r * Math.cos(th) * asp * sx, uy = r * Math.sin(th) * sy;
      const px = b.cx + dx + ux * c - uy * s, py = b.cy + dy + ux * s + uy * c;
      if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
  }
  // A polygon given as points, its edges roughened like scissors on paper.
  function cutPoly(ctx, pts, rng, amt = 0.004) {
    const dense = [];
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length], n = Math.max(2, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 0.01));
      for (let j = 0; j < n; j++) dense.push([lerp(a[0], b[0], j / n), lerp(a[1], b[1], j / n)]);
    }
    const nz = noise1(rng, 3), { nx, ny } = normals(dense, 1);
    ctx.beginPath();
    dense.forEach(([x, y], i) => { const d = amt * nz(i * 0.3); i ? ctx.lineTo(x + nx[i] * d, y + ny[i] * d) : ctx.moveTo(x + nx[i] * d, y + ny[i] * d); });
    ctx.closePath();
  }
  function circle(ctx, x, y, r) { ctx.beginPath(); ctx.arc(x, y, Math.max(r, 0), 0, TAU); }

  // ---------- print finish ----------
  // Paper: soft clouding, fine tooth and a few fibres, laid over with
  // 'overlay'. Speckle: paper-coloured flecks that only show on ink, as in
  // a risograph. Both are cached rasters drawn in device pixels.
  let paperCanvas = null;
  const speckles = new Map();
  const patCache = new WeakMap();
  function paperTex() {
    if (paperCanvas) return paperCanvas;
    const N = 256, cv = document.createElement('canvas'); cv.width = cv.height = N;
    const g = cv.getContext('2d'), r = makeRng('paper'), img = g.createImageData(N, N);
    // value noise at two scales, tileable
    const grid = (k) => { const a = []; for (let i = 0; i < k * k; i++) a.push(r.next()); return (x, y) => { const gx = (x / N) * k, gy = (y / N) * k, x0 = Math.floor(gx), y0 = Math.floor(gy), fx = gx - x0, fy = gy - y0; const v = (i, j) => a[((j % k) * k + (i % k))]; const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy); return lerp(lerp(v(x0, y0), v(x0 + 1, y0), sx), lerp(v(x0, y0 + 1), v(x0 + 1, y0 + 1), sx), sy); }; };
    const big = grid(6), mid = grid(24);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const v = 128 + (big(x, y) - 0.5) * 34 + (mid(x, y) - 0.5) * 26 + (r.next() - 0.5) * 46;
      const i = (y * N + x) * 4; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    g.lineCap = 'round';
    for (let i = 0; i < 70; i++) {
      const x = r.next() * N, y = r.next() * N, a = r.next() * TAU, l = 4 + r.next() * 14;
      g.strokeStyle = r.chance(0.5) ? 'rgba(255,255,255,.35)' : 'rgba(0,0,0,.22)'; g.lineWidth = 0.6;
      g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(a + 0.6) * l / 2, y + Math.sin(a + 0.6) * l / 2, x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
    }
    return (paperCanvas = cv);
  }
  function speckleTex(col) {
    const key = hex(col);
    if (speckles.has(key)) return speckles.get(key);
    const N = 128, cv = document.createElement('canvas'); cv.width = cv.height = N;
    const g = cv.getContext('2d'), r = makeRng('speckle'), v = rgb(col);
    for (let i = 0; i < 520; i++) {
      g.fillStyle = `rgba(${v[0] | 0},${v[1] | 0},${v[2] | 0},${0.35 + r.next() * 0.6})`;
      const s = r.chance(0.85) ? 1 : 2; g.fillRect(Math.floor(r.next() * N), Math.floor(r.next() * N), s, s);
    }
    speckles.set(key, cv);
    return cv;
  }
  function pattern(ctx, cv, S, scale = 1) {
    let m = patCache.get(ctx); if (!m) { m = new Map(); patCache.set(ctx, m); }
    let p = m.get(cv); if (!p) { p = ctx.createPattern(cv, 'repeat'); m.set(cv, p); }
    p.setTransform(new DOMMatrix().scale(scale / S));
    return p;
  }
  // Lay the print finish over whatever is drawn in the unit square.
  function finish(ctx, c, S, o = {}) {
    const dpr = o.dpr || 1;
    ctx.save();
    ctx.globalCompositeOperation = 'overlay';
    ctx.globalAlpha = o.paper ?? (c.lightPaper ? 0.16 : 0.2);
    ctx.fillStyle = pattern(ctx, paperTex(), S, dpr);
    ctx.fillRect(0, 0, 1, 1);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = o.speckle ?? 0.5;
    ctx.fillStyle = pattern(ctx, speckleTex(c.tile), S, dpr);
    ctx.fillRect(0, 0, 1, 1);
    if (o.vignette !== 0) {
      ctx.globalAlpha = 1;
      const g = ctx.createRadialGradient(0.5, 0.5, 0.35, 0.5, 0.5, 0.75);
      g.addColorStop(0, css(c.deep, 0)); g.addColorStop(1, css(c.deep, o.vignette ?? 0.1));
      ctx.fillStyle = g; ctx.fillRect(0, 0, 1, 1);
    }
    ctx.restore();
  }
  // Overprint mode for a second ink: multiply on paper, screen on dark.
  const overprint = (c) => (c.lightPaper ? 'multiply' : 'screen');

  return {
    TAU, BREATH, hash, makeRng, noise1, clamp, lerp, ss, easeOut, easeInOut, prog, breathAt,
    rgb, mix, css, hex, lum, contrast, darker, lighter, roles,
    resample, normals, makeStroke, drawStroke, pen, jitterPts,
    makeBlob, blobPath, cutPoly, circle, finish, overprint, paperTex, pattern,
  };
})();
