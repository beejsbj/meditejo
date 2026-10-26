/* Meditejo mark generator.
 *
 * A seed string ("g-4kq2", "a-…", "m-…") builds a mark: the prefix picks the
 * family (g gesture on form, a atmospheric, m minimal) and the rest feeds a
 * seeded PRNG, so the same seed always gives the same mark. Drawing is plain
 * Canvas 2D in a unit square (0..1), which maps one to one onto a Flutter
 * CustomPainter: Path.lineTo, fill, linear and radial gradients, clip.
 *
 * MarkGen.build(seed)                 -> mark (pure data)
 * MarkGen.draw(ctx, mark, pal, t, o)  -> paints frame at t seconds
 *   ctx is already scaled so the unit square fills the target.
 *   o.still: draw the settled frame (reduced motion, icons, export).
 *   o.bg === false: no tile behind gesture and minimal marks.
 *   o.scale: content scale about the centre (icons use < 1).
 */
const MarkGen = (() => {
  'use strict';
  const TAU = Math.PI * 2;
  const BREATH = 10; // seconds per breath: six a minute, as the app's mark

  // ---------- seeded randomness ----------
  function hash(str) {
    let h = 1779033703 ^ str.length;
    for (let i = 0; i < str.length; i++) {
      h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
      h = (h << 13) | (h >>> 19);
    }
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return (h ^ (h >>> 16)) >>> 0;
  }
  function makeRng(str) {
    let a = hash(str);
    const next = () => {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    return {
      next,
      range: (lo, hi) => lo + (hi - lo) * next(),
      int: (lo, hi) => Math.floor(lo + (hi - lo + 1) * next()),
      pick: (arr) => arr[Math.floor(next() * arr.length)],
      sign: () => (next() < 0.5 ? -1 : 1),
      chance: (p) => next() < p,
    };
  }
  // Smooth 1-D noise: a few sines with seeded frequency and phase, in -1..1.
  function noise1(rng, oct = 3) {
    const f = [], p = [], a = [];
    let tot = 0;
    for (let i = 0; i < oct; i++) {
      f.push(rng.range(0.8, 1.5) * Math.pow(2.13, i));
      p.push(rng.range(0, TAU));
      a.push(Math.pow(0.5, i));
      tot += a[i];
    }
    return (x) => {
      let s = 0;
      for (let i = 0; i < oct; i++) s += a[i] * Math.sin(f[i] * x + p[i]);
      return s / tot;
    };
  }

  // ---------- small maths ----------
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const ss = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const easeOut = (t) => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
  const easeInOut = (t) => -(Math.cos(Math.PI * clamp(t, 0, 1)) - 1) / 2;
  const prog = (t, start, dur) => clamp((t - start) / dur, 0, 1);

  // ---------- colour ----------
  const rgbCache = new Map();
  function rgb(c) {
    if (Array.isArray(c)) return c;
    let v = rgbCache.get(c);
    if (!v) {
      const h = c.replace('#', '');
      v = [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
      rgbCache.set(c, v);
    }
    return v;
  }
  const mix = (a, b, t) => { const x = rgb(a), y = rgb(b); return [lerp(x[0], y[0], t), lerp(x[1], y[1], t), lerp(x[2], y[2], t)]; };
  const css = (c, alpha = 1) => { const v = rgb(c); return `rgba(${v[0] | 0},${v[1] | 0},${v[2] | 0},${alpha})`; };
  function lum(c) {
    const v = rgb(c).map((x) => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); });
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
  }
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const darker = (a, b) => (lum(a) < lum(b) ? a : b);
  const lighter = (a, b) => (lum(a) < lum(b) ? b : a);

  // ---------- palettes ----------
  // tile, form, stroke, accent are the mark's four roles; ui holds the app's
  // neutrals (bg, surface, raised, text, muted) for light and dark.
  const palettes = [
    { id: 'clay', name: 'Clay', mood: 'Warm earth in the Duet spirit: terracotta, ochre, cream and ink.',
      tile: '#F6F1E8', form: '#D2754E', stroke: '#1C1916', accent: '#D9A13F',
      ui: { light: { bg: '#FAF6EF', surface: '#F1E9DD', raised: '#EADFCF', text: '#2A221B', muted: '#7A6B5D' },
            dark: { bg: '#191512', surface: '#241E19', raised: '#2E2620', text: '#F2E9DD', muted: '#A79482' } } },
    { id: 'dusk', name: 'Dusk', mood: 'The hour before sleep: indigo, plum and a lamp of amber.',
      tile: '#211E45', form: '#7B4475', stroke: '#F2B65E', accent: '#E8846A',
      ui: { light: { bg: '#F6F3F8', surface: '#ECE6F1', raised: '#E2D9EA', text: '#211C3A', muted: '#6C6585' },
            dark: { bg: '#12102A', surface: '#1C1938', raised: '#262247', text: '#EEE8F6', muted: '#A097BA' } } },
    { id: 'forest', name: 'Forest', mood: 'Moss on bark under morning mist; deeper than the current sage.',
      tile: '#E8EBE2', form: '#7E8E52', stroke: '#2C241D', accent: '#C9A15A',
      ui: { light: { bg: '#F3F4EE', surface: '#E6E9DF', raised: '#DBE0D2', text: '#22271E', muted: '#687160' },
            dark: { bg: '#121611', surface: '#1B211A', raised: '#252C23', text: '#E5EADE', muted: '#949E8B' } } },
    { id: 'sumi', name: 'Sumi', mood: 'Ink on paper. Nothing but value, so form has to carry it.',
      tile: '#F3F0E9', form: '#BCB5A8', stroke: '#141413', accent: '#6E685F',
      ui: { light: { bg: '#F7F5F0', surface: '#ECE8E0', raised: '#E2DDD3', text: '#161514', muted: '#76716A' },
            dark: { bg: '#111110', surface: '#1B1A19', raised: '#252422', text: '#EDEAE3', muted: '#8F8A82' } } },
    { id: 'riso', name: 'Lotus Riso', mood: 'The surprise: blush paper, lotus pink and blue ink, like a risograph print.',
      tile: '#F7EAE4', form: '#EC9C8C', stroke: '#24346E', accent: '#F2C14E',
      ui: { light: { bg: '#FBF4F0', surface: '#F4E6E0', raised: '#EDDAD2', text: '#1F2647', muted: '#6E6A80' },
            dark: { bg: '#121528', surface: '#1B1F38', raised: '#252A48', text: '#F4E9E4', muted: '#A39CB3' } } },
    { id: 'lagoon', name: 'Lagoon', mood: 'Night water: deep teal, a lit lagoon and sand-coloured light.',
      tile: '#0F2D33', form: '#3F8C83', stroke: '#F1E2C2', accent: '#EE8D68',
      ui: { light: { bg: '#F1F5F3', surface: '#E3ECE9', raised: '#D5E3DF', text: '#13292C', muted: '#5F7472' },
            dark: { bg: '#0B1C20', surface: '#12282D', raised: '#1A343A', text: '#E9EFEA', muted: '#8EA5A2' } } },
  ];

  // ---------- seeds ----------
  const FAMILIES = { g: 'gesture', a: 'atmos', m: 'minimal' };
  const PREFIX = { gesture: 'g', atmos: 'a', minimal: 'm' };
  const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
  function randomSeed(family) {
    let s = '';
    for (let i = 0; i < 4; i++) s += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    return PREFIX[family] + '-' + s;
  }
  function normaliseSeed(input) {
    const s = String(input).trim().toLowerCase().replace(/\s+/g, '-');
    if (/^[gam]-[a-z0-9-]+$/.test(s)) return s;
    return 'g-' + (s || '0');
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
  function normals(pts) {
    const n = pts.length, nx = new Float64Array(n), ny = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const a = pts[Math.max(i - 1, 0)], b = pts[Math.min(i + 1, n - 1)];
      const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy) || 1;
      nx[i] = -dy / l; ny[i] = dx / l;
    }
    return { nx, ny };
  }
  // Width along the stroke, s in 0..1.
  function profile(kind, s) {
    switch (kind) {
      case 'brush': // heavy landing, a dry tail
        return (0.66 + 0.34 * ss(0, 0.05, s)) * (1 - 0.8 * Math.pow(ss(0.4, 1, s), 1.25)) + 0.05;
      case 'grow': // from a fine centre outwards
        return (0.42 + 0.58 * ss(0, 0.5, s)) * (1 - 0.45 * ss(0.86, 1, s));
      case 'swell':
        return 0.5 + 0.5 * Math.pow(Math.sin(Math.PI * clamp(s * 1.04 - 0.02, 0, 1)), 0.7);
      default: // marker: blunt start, slight lift at the end
        return (0.74 + 0.26 * ss(0, 0.05, s)) * (1 - 0.36 * ss(0.88, 1, s));
    }
  }
  // Turn a raw centreline into a hand-drawn ribbon: even spacing, a slow
  // wobble across the line, varying pressure, an optional nib angle, and a
  // pen clock that slows in tight curves as a hand does.
  function makeStroke(raw, o, rng) {
    const N = o.samples || 420;
    let { pts } = resample(raw, N);
    let { nx, ny } = normals(pts);
    const wob = noise1(rng, 3), wf = rng.range(3, 6);
    pts = pts.map((p, i) => { const d = o.wobble * wob((i / (N - 1)) * wf); return [p[0] + nx[i] * d, p[1] + ny[i] * d]; });
    const r = resample(pts, N);
    pts = r.pts;
    ({ nx, ny } = normals(pts));
    const pn = noise1(rng, 2), pf = rng.range(4, 8), nibA = rng.range(0, Math.PI);
    const x = new Float64Array(N), y = new Float64Array(N), w = new Float64Array(N), cost = new Float64Array(N);
    const ds = r.len / (N - 1);
    let prevAng = null;
    for (let i = 0; i < N; i++) {
      const s = i / (N - 1);
      x[i] = pts[i][0]; y[i] = pts[i][1];
      const ang = Math.atan2(-nx[i], ny[i]);
      let ww = o.width * profile(o.taper, s) * (1 + o.pressure * pn(s * pf));
      if (o.nib) ww *= 1 - o.nib + o.nib * (0.3 + 0.7 * Math.abs(Math.sin(ang - nibA)));
      w[i] = ww;
      if (i > 0) {
        let da = Math.abs(ang - prevAng);
        if (da > Math.PI) da = TAU - da;
        cost[i] = cost[i - 1] + ds + 0.014 * da;
      }
      prevAng = ang;
    }
    for (let i = 0; i < N; i++) cost[i] /= cost[N - 1];
    return { n: N, x, y, nx, ny, w, cost, len: r.len };
  }
  // Fill the ribbon from the start up to pen-clock p (0..1). The outline is
  // one polygon (left side out, right side back) with round caps; nonzero
  // fill keeps self-crossings solid and loop holes open.
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

  // Centrelines. Each returns raw [x, y] points, y down, any scale.
  const centrelines = {
    // Cursive loops ("ee"): a prolate trochoid whose loops rise above a
    // baseline, eased in from a flat lead and out into a rising exit.
    loops(rng) {
      const n = rng.pick([1, 2, 2, 2, 3]);
      const d = rng.range(2.3, 3.2), h = rng.range(4.4, 5.8);
      const lead = rng.range(2.2, 3.4), exit = rng.range(2.4, 3.6), lift = rng.range(1.2, 3.4);
      const sag = rng.range(0, 1.0), hn = noise1(rng, 2);
      const t0 = -lead, t1 = TAU * n + exit, out = [];
      for (let i = 0; i <= 900; i++) {
        const t = lerp(t0, t1, i / 900);
        const env = ss(t0 + 0.4, 0.4, t) * (1 - ss(TAU * n - 0.3, TAU * n + 1.4, t));
        const amp = 1 + 0.12 * hn(t * 0.35);
        let px = t + d * env * Math.sin(t);
        let py = -h * amp * env * (1 - Math.cos(t)) / 2;
        py -= lift * Math.pow(ss(TAU * n - 0.6, t1, t), 1.6);
        py += sag * Math.sin(Math.PI * clamp((t - t0) / (lead + 0.5), 0, 1));
        out.push([px, py]);
      }
      return out;
    },
    // Ensō: one open circle, slightly spiralling in, brush-weighted.
    enso(rng) {
      const th0 = rng.range(0, TAU), sweep = rng.range(1.68, 1.9) * Math.PI;
      const asp = rng.range(0.92, 1.04), dir = rng.sign(), rn = noise1(rng, 3), out = [];
      for (let i = 0; i <= 600; i++) {
        const u = i / 600, th = th0 + dir * sweep * u;
        const r = (1 + 0.035 * rn(u * 4)) * (1 - 0.07 * u);
        out.push([r * Math.cos(th) * asp, r * Math.sin(th)]);
      }
      return out;
    },
    // One slow breath: a wave that swells and settles.
    wave(rng) {
      const cyc = rng.range(1.0, 1.55), A = rng.range(0.15, 0.24), ph = rng.range(-0.5, 0.3), out = [];
      for (let i = 0; i <= 600; i++) {
        const u = i / 600, env = Math.pow(Math.sin(Math.PI * (0.06 + 0.88 * u)), 0.6);
        out.push([-1 + 2 * u, -A * env * Math.sin(TAU * cyc * u + ph)]);
      }
      return out;
    },
    // A spiral that starts at the centre and unwinds into a tail.
    spiral(rng) {
      const turns = rng.range(1.15, 1.6), dir = rng.sign(), th0 = rng.range(0, TAU);
      const tail = rng.range(0.3, 0.6), r0 = 0.26, out = [];
      for (let i = 0; i <= 900; i++) {
        const u = i / 900, th = th0 + dir * TAU * turns * u;
        const r = r0 + (1 - r0) * Math.pow(u, 0.9) + tail * Math.pow(ss(0.78, 1, u), 2);
        out.push([r * Math.cos(th), r * Math.sin(th)]);
      }
      return out;
    },
    // Cursive arches, a quiet "m": a cycloid with cusps on the baseline.
    arches(rng) {
      const n = rng.pick([2, 3, 3]), d = rng.range(0.92, 1.2), h = rng.range(1.9, 2.6);
      const lead = rng.range(1.8, 2.8), exit = rng.range(2.4, 3.6), lift = rng.range(0.5, 1.8), out = [];
      const t0 = -lead, t1 = TAU * n + exit;
      for (let i = 0; i <= 900; i++) {
        const t = lerp(t0, t1, i / 900);
        const env = ss(t0 + 0.3, 0.2, t) * (1 - ss(TAU * n - 0.1, TAU * n + 1.2, t));
        const px = t - d * env * Math.sin(t);
        let py = -h * env * (1 - Math.cos(t));
        py -= lift * Math.pow(ss(TAU * n - 0.4, t1, t), 1.6);
        out.push([px, py]);
      }
      return out;
    },
    // Infinity: one open lemniscate, a breath in and a breath out.
    infinity(rng) {
      const t0 = rng.range(0, TAU), span = TAU * rng.range(1.03, 1.1), asp = rng.range(0.85, 1.15), out = [];
      for (let i = 0; i <= 700; i++) {
        const t = t0 + span * (i / 700), s = Math.sin(t), den = 1 + s * s;
        out.push([Math.cos(t) / den, (asp * s * Math.cos(t)) / den]);
      }
      return out;
    },
  };
  const STROKE_LABEL = { loops: 'loops', enso: 'ensō', wave: 'breath wave', spiral: 'spiral', arches: 'arches · m', infinity: 'infinity' };

  function bbox(pts) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0, cx: (x0 + x1) / 2, cy: (y0 + y1) / 2 };
  }
  // Place a centreline: scale to a target width (or diameter), rotate, move.
  function place(raw, { width, maxH, rot, cx, cy, round }) {
    const b = bbox(raw);
    let s = round ? width / Math.max(b.w, b.h) : width / b.w;
    if (b.h * s > maxH) s = maxH / b.h;
    const c = Math.cos(rot), sn = Math.sin(rot);
    return raw.map(([x, y]) => {
      const u = (x - b.cx) * s, v = (y - b.cy) * s;
      return [cx + u * c - v * sn, cy + u * sn + v * c];
    });
  }

  // ---------- organic closed shapes ----------
  function makeBlob(rng, cx, cy, R, rough = 1) {
    return {
      cx, cy, R, rot: rng.range(0, TAU), asp: rng.range(0.9, 1.08),
      a: [rng.range(0.03, 0.08) * rough, rng.range(0.015, 0.045) * rough, rng.range(0, 0.018) * rough],
      p: [rng.range(0, TAU), rng.range(0, TAU), rng.range(0, TAU)],
      drift: [rng.range(0.6, 1.4), rng.range(0.6, 1.4), rng.range(0.6, 1.4)],
    };
  }
  // morph: 0..1 slow shape change; grow: radius scale.
  function blobPath(ctx, b, grow = 1, morph = 0, dx = 0, dy = 0) {
    ctx.beginPath();
    const M = 120;
    for (let i = 0; i <= M; i++) {
      const th = (i / M) * TAU;
      let r = 1;
      for (let k = 0; k < 3; k++) r += b.a[k] * Math.sin((k + 2) * th + b.p[k] + morph * b.drift[k]);
      r *= b.R * grow;
      const ux = r * Math.cos(th) * b.asp, uy = r * Math.sin(th);
      const c = Math.cos(b.rot), s = Math.sin(b.rot);
      const px = b.cx + dx + ux * c - uy * s, py = b.cy + dy + ux * s + uy * c;
      if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
  }
  function circle(ctx, x, y, r) { ctx.beginPath(); ctx.arc(x, y, Math.max(r, 0), 0, TAU); }

  // ---------- build ----------
  function build(seedInput, forceType) {
    const seed = normaliseSeed(seedInput);
    const family = FAMILIES[seed[0]];
    const rng = makeRng(seed);
    const m = family === 'gesture' ? buildGesture(rng, forceType) : family === 'atmos' ? buildAtmos(rng, forceType) : buildMinimal(rng, forceType);
    m.seed = seed;
    m.family = family;
    return m;
  }

  function buildGesture(rng, forceType) {
    const type = forceType || rng.pick(['loops', 'loops', 'enso', 'wave', 'spiral', 'arches', 'infinity']);
    const bx = 0.5 + rng.range(-0.055, 0.055), by = 0.5 + rng.range(-0.04, 0.05);
    const R = type === 'enso' || type === 'spiral' ? rng.range(0.22, 0.27) : rng.range(0.27, 0.32);
    const blob = makeBlob(rng, bx, by, R);
    const raw = centrelines[type](rng);
    let placed, sty;
    const widthBase = rng.range(0.038, 0.05);
    if (type === 'enso') {
      placed = place(raw, { width: R * 2 * rng.range(1.08, 1.28), maxH: 0.7, rot: 0, cx: 0.5 - (bx - 0.5) * 0.8 + rng.range(-0.02, 0.02), cy: 0.5 - (by - 0.5) * 0.8, round: true });
      sty = { taper: 'brush', width: widthBase * 1.45, wobble: 0.0035, pressure: 0.12, nib: 0 };
    } else if (type === 'spiral') {
      placed = place(raw, { width: R * 2 * rng.range(0.95, 1.2), maxH: 0.66, rot: 0, cx: bx + rng.range(-0.06, 0.06), cy: by + rng.range(-0.04, 0.04), round: true });
      sty = { taper: 'grow', width: widthBase * 1.05, wobble: 0.003, pressure: 0.1, nib: 0.25 };
    } else if (type === 'infinity') {
      placed = place(raw, { width: rng.range(0.56, 0.68), maxH: 0.36, rot: rng.range(-0.25, 0.25), cx: 0.5 + rng.range(-0.02, 0.02), cy: by + rng.range(-0.02, 0.05) });
      sty = { taper: 'marker', width: widthBase, wobble: 0.003, pressure: 0.12, nib: 0.2 };
    } else {
      const W = type === 'loops' ? rng.range(0.7, 0.82) : type === 'arches' ? rng.range(0.6, 0.74) : rng.range(0.64, 0.78);
      placed = place(raw, { width: W, maxH: 0.42, rot: rng.range(-0.14, 0.08), cx: 0.5 + rng.range(-0.03, 0.03), cy: by + rng.range(0.0, 0.08) });
      sty = { taper: type === 'wave' ? 'swell' : 'marker', width: widthBase, wobble: 0.004, pressure: 0.13, nib: type === 'arches' ? 0.3 : rng.chance(0.4) ? 0.22 : 0 };
    }
    const stroke = makeStroke(placed, sty, rng);
    // Keep the whole composition inside the adaptive-icon safe circle
    // (radius 0.458 of the visible icon), with a little air.
    let maxd = 0;
    for (let i = 0; i < stroke.n; i++) maxd = Math.max(maxd, Math.hypot(stroke.x[i] - 0.5, stroke.y[i] - 0.5) + stroke.w[i] / 2);
    maxd = Math.max(maxd, Math.hypot(bx - 0.5, by - 0.5) + R * 1.13);
    const fit = Math.min(1, 0.44 / maxd);
    const dur = clamp(1.3 + 0.75 * stroke.len, 2.1, 3.6);
    return { type, label: STROKE_LABEL[type], blob, stroke, fit, dur };
  }

  function buildAtmos(rng, forceType) {
    const type = forceType || rng.pick(['sunrise', 'mist', 'halo', 'veil', 'ripple']);
    const m = { type, label: type, fit: 1 };
    if (type === 'sunrise') {
      m.h = rng.range(0.58, 0.67); m.sr = rng.range(0.15, 0.2); m.sx = 0.5 + rng.range(-0.07, 0.07);
      m.sy = m.h - m.sr * rng.range(0.15, 0.7); m.glow = rng.range(2.1, 2.9);
      m.bars = Array.from({ length: rng.int(4, 6) }, (_, i) => ({ ph: rng.range(0, TAU), j: rng.range(-0.03, 0.03) }));
    } else if (type === 'mist') {
      const n = rng.int(3, 4);
      m.sun = { x: 0.5 + rng.range(-0.14, 0.14), y: rng.range(0.32, 0.42), r: rng.range(0.12, 0.17) };
      m.layers = Array.from({ length: n }, (_, i) => ({
        y: lerp(0.5, 0.78, n === 1 ? 0 : i / (n - 1)) + rng.range(-0.02, 0.02),
        amp: rng.range(0.025, 0.06) * (1 - i * 0.12), f: rng.range(0.6, 1.4), ph: rng.range(0, TAU),
        f2: rng.range(1.8, 2.8), ph2: rng.range(0, TAU), per: rng.range(26, 40),
      }));
    } else if (type === 'halo') {
      const ox = rng.range(-0.04, 0.04), oy = rng.range(-0.04, 0.04);
      m.orb = { x: 0.5 + ox, y: 0.5 + oy, r: rng.range(0.15, 0.2) };
      const raw = centrelines.enso(rng);
      const placed = place(raw, { width: rng.range(0.56, 0.66), maxH: 0.7, rot: 0, cx: 0.5 - ox * 1.2, cy: 0.5 - oy * 1.2, round: true });
      m.ring = makeStroke(placed, { taper: 'brush', width: rng.range(0.03, 0.04), wobble: 0.003, pressure: 0.12, nib: 0 }, rng);
      m.dur = 2.6;
    } else if (type === 'veil') {
      const n = rng.int(2, 3), r = rng.range(0.19, 0.24), sep = rng.range(0.12, 0.16), rot = rng.range(0, TAU);
      m.discs = Array.from({ length: n }, (_, i) => {
        const a = rot + (i * TAU) / n;
        return { ax: Math.cos(a), ay: Math.sin(a), r: r * (i === 2 ? 0.82 : 1), role: ['form', 'accent', 'deep'][i] };
      });
      m.sep = sep;
    } else {
      m.h = rng.range(0.5, 0.56);
      m.moon = { x: 0.5 + rng.range(-0.08, 0.08), y: rng.range(0.26, 0.31), r: rng.range(0.12, 0.15) };
      m.pond = { x: m.moon.x + rng.range(-0.03, 0.03), y: m.h + rng.range(0.17, 0.22) };
      m.rings = rng.int(3, 4); m.per = rng.range(8, 11);
    }
    return m;
  }

  function buildMinimal(rng, forceType) {
    const type = forceType || rng.pick(['split', 'arch', 'pebble', 'crescent', 'vesica', 'cairn']);
    const LABEL = { split: 'split sun', arch: 'arch', pebble: 'pebble & bindu', crescent: 'crescent', vesica: 'vesica', cairn: 'cairn' };
    const m = { type, label: LABEL[type], fit: 1, rough: rng.range(0.15, 0.4) };
    const shape = (cx, cy, R) => makeBlob(rng, cx, cy, R, m.rough);
    if (type === 'split') {
      const r = rng.range(0.27, 0.31);
      m.disc = shape(0.5, 0.5, r); m.disc.asp = 1; m.disc.rot = 0;
      m.h = 0.5 + r * rng.range(0.05, 0.38); m.gap = rng.range(0.024, 0.036); m.shift = rng.range(-0.035, 0.035);
      m.top = rng.pick(['form', 'accent']);
    } else if (type === 'arch') {
      m.w = rng.range(0.38, 0.46); m.ht = rng.range(0.54, 0.62); m.cy = 0.5 + rng.range(0, 0.03);
      m.sun = rng.range(0.09, 0.12); m.sunY = rng.range(0.25, 0.55); m.sunRole = rng.pick(['accent', 'tile', 'stroke']);
    } else if (type === 'pebble') {
      m.peb = shape(0.5 + rng.range(-0.05, 0.05), 0.5 + rng.range(-0.04, 0.04), rng.range(0.25, 0.3));
      const a = rng.range(0, TAU), d = rng.range(0.25, 0.6);
      m.dot = { x: m.peb.cx + Math.cos(a) * m.peb.R * d, y: m.peb.cy + Math.sin(a) * m.peb.R * d, r: rng.range(0.045, 0.065) };
      m.second = rng.chance(0.5) ? shape(m.peb.cx - Math.cos(a) * m.peb.R * 0.85, m.peb.cy - Math.sin(a) * m.peb.R * 0.85, rng.range(0.09, 0.13)) : null;
    } else if (type === 'crescent') {
      m.r = rng.range(0.26, 0.3); const a = rng.range(-2.6, -0.5) + (rng.chance(0.5) ? Math.PI : 0);
      m.cut = { ax: Math.cos(a), ay: Math.sin(a), d: rng.range(0.13, 0.2) };
      m.dot = rng.chance(0.7) ? rng.range(0.035, 0.05) : 0;
    } else if (type === 'vesica') {
      m.r = rng.range(0.2, 0.24); m.sep = rng.range(0.17, 0.24); m.rot = rng.chance(0.6) ? 0 : rng.range(-0.8, 0.8);
      m.mid = rng.pick(['stroke', 'stroke', 'tile']);
    } else {
      const sizes = [rng.range(0.2, 0.24), rng.range(0.14, 0.17), rng.range(0.08, 0.11)];
      let y = 0.8;
      m.stones = sizes.map((rx, i) => {
        const ry = rx * rng.range(0.5, 0.62); y -= ry; const s = shape(0.5 + rng.range(-0.03, 0.03), y, 1); y -= ry * 0.92;
        s.R = 1; s.rx = rx; s.ry = ry; return s;
      });
      const span = 0.8 - y, shift = (1 - span) / 2 - y;
      m.stones.forEach((s) => { s.cy += shift; });
    }
    return m;
  }

  // ---------- grain ----------
  const grainCache = new WeakMap();
  let grainCanvas = null;
  function grain(ctx, S, alpha) {
    if (!grainCanvas) {
      grainCanvas = document.createElement('canvas');
      grainCanvas.width = grainCanvas.height = 128;
      const g = grainCanvas.getContext('2d'), img = g.createImageData(128, 128), r = makeRng('grain');
      for (let i = 0; i < img.data.length; i += 4) { const v = 128 + (r.next() - 0.5) * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
      g.putImageData(img, 0, 0);
    }
    let pat = grainCache.get(ctx);
    if (!pat) { pat = ctx.createPattern(grainCanvas, 'repeat'); grainCache.set(ctx, pat); }
    pat.setTransform(new DOMMatrix().scale(1 / S));
    ctx.save();
    ctx.globalCompositeOperation = 'overlay';
    ctx.globalAlpha = alpha;
    ctx.fillStyle = pat;
    ctx.fillRect(0, 0, 1, 1);
    ctx.restore();
  }

  // ---------- draw ----------
  // Breath: 0 (out) to 1 (in), starting at rest once the entrance settles.
  const breathAt = (t, start) => (t < start ? 0 : 0.5 - 0.5 * Math.cos((TAU * (t - start)) / BREATH));

  function draw(ctx, m, pal, t, o = {}) {
    const S = o.px || 256;
    if (o.still) t = 60;
    const c = { tile: pal.tile, form: pal.form, stroke: pal.stroke, accent: pal.accent, ...(o.colors || {}) };
    c.deep = darker(c.tile, c.stroke); c.light = lighter(c.tile, c.stroke);
    const sc = (o.scale || 1) * m.fit;
    if (m.family === 'atmos') {
      ctx.save();
      drawAtmos(ctx, m, c, t, o, sc);
      ctx.restore();
      if (o.grain !== false) grain(ctx, S, lum(c.tile) > 0.4 ? 0.07 : 0.085);
      return;
    }
    if (o.bg !== false) { ctx.fillStyle = css(c.tile); ctx.fillRect(0, 0, 1, 1); }
    ctx.save();
    ctx.translate(0.5, 0.5); ctx.scale(sc, sc); ctx.translate(-0.5, -0.5);
    if (m.family === 'gesture') drawGesture(ctx, m, c, t, o);
    else drawMinimal(ctx, m, c, t, o);
    ctx.restore();
  }

  function drawGesture(ctx, m, c, t, o) {
    const strokeStart = 0.5, bStart = strokeStart + m.dur + 0.4;
    const b = o.still ? 0 : breathAt(t, bStart);
    const appear = easeOut(prog(t, 0, 1.0));
    const morph = o.still ? 0 : Math.max(0, t - bStart) * 0.05;
    const p = o.still ? 1 : easeInOut(prog(t, strokeStart, m.dur));
    ctx.globalAlpha = appear;
    ctx.fillStyle = css(c.form);
    blobPath(ctx, m.blob, (0.9 + 0.1 * appear) * (1 + 0.028 * b), morph);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.save();
    ctx.translate(0.5, 0.5 - 0.006 * b); ctx.scale(1 + 0.008 * b, 1 + 0.008 * b); ctx.translate(-0.5, -0.5);
    ctx.fillStyle = css(c.stroke);
    drawStroke(ctx, m.stroke, p);
    ctx.restore();
  }

  function drawMinimal(ctx, m, c, t, o) {
    const b = o.still ? 0 : breathAt(t, 2.4);
    const e1 = o.still ? 1 : easeOut(prog(t, 0, 1.1)), e2 = o.still ? 1 : easeOut(prog(t, 0.6, 1.3)), e3 = o.still ? 1 : easeOut(prog(t, 1.1, 1.2));
    const fill = (role) => { ctx.fillStyle = css(c[role]); ctx.fill(); };
    if (m.type === 'split') {
      const d = m.disc, gy = m.h;
      ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 1, gy - m.gap / 2); ctx.clip();
      blobPath(ctx, d, 1 + 0.02 * b, 0, 0, (1 - e1) * 0.12 - 0.006 * b); fill(m.top);
      ctx.restore();
      ctx.save(); ctx.beginPath(); ctx.rect(0, gy + m.gap / 2, 1, 1); ctx.clip();
      ctx.globalAlpha = e2;
      blobPath(ctx, d, 1, 0, m.shift * e2, 0.004 * b); fill('stroke');
      ctx.restore();
    } else if (m.type === 'arch') {
      const w = m.w, top = m.cy - m.ht / 2, bot = m.cy + m.ht / 2, x0 = 0.5 - w / 2, x1 = 0.5 + w / 2;
      const grow = e1, archTop = lerp(bot, top, grow);
      ctx.save(); ctx.beginPath(); ctx.rect(0, archTop - 0.01, 1, 1); ctx.clip();
      ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0, top + w / 2); ctx.arc(0.5, top + w / 2, w / 2, Math.PI, 0); ctx.lineTo(x1, bot); ctx.closePath();
      fill('form'); ctx.restore();
      const sy = lerp(bot - m.sun, top + w / 2 + m.ht * (m.sunY - 0.25) * 0.8, e2) - 0.01 * b;
      ctx.save(); ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0, top + w / 2); ctx.arc(0.5, top + w / 2, w / 2, Math.PI, 0); ctx.lineTo(x1, bot); ctx.closePath(); ctx.clip();
      circle(ctx, 0.5, sy, m.sun * (1 + 0.04 * b)); ctx.globalAlpha = e2; fill(m.sunRole); ctx.restore();
    } else if (m.type === 'pebble') {
      ctx.globalAlpha = e1; blobPath(ctx, m.peb, (0.92 + 0.08 * e1) * (1 + 0.02 * b), b * 0.3); fill('form'); ctx.globalAlpha = 1;
      if (m.second) { ctx.globalAlpha = e3; blobPath(ctx, m.second, (0.6 + 0.4 * e3) * (1 - 0.03 * b), b * 0.3); fill('accent'); ctx.globalAlpha = 1; }
      circle(ctx, m.dot.x, m.dot.y - (1 - e2) * 0.08, m.dot.r * e2 * (1 + 0.06 * b)); fill('stroke');
    } else if (m.type === 'crescent') {
      const d = lerp(0.62, m.cut.d, e2) * (1 + 0.06 * b), cx = 0.5 + m.cut.ax * d, cy = 0.5 + m.cut.ay * d;
      ctx.save(); circle(ctx, 0.5, 0.5, m.r * (0.92 + 0.08 * e1)); ctx.clip();
      ctx.beginPath(); ctx.rect(-1, -1, 3, 3); ctx.arc(cx, cy, m.r * 1.02, 0, TAU); ctx.globalAlpha = e1; ctx.fillStyle = css(c.form); ctx.fill('evenodd');
      ctx.restore();
      if (m.dot) { circle(ctx, 0.5 + m.cut.ax * m.r * 0.62, 0.5 + m.cut.ay * m.r * 0.62, m.dot * e3); fill('accent'); }
    } else if (m.type === 'vesica') {
      const sep = lerp(m.sep * 2.6, m.sep, e1) * (1 - 0.08 * b), ca = Math.cos(m.rot), sa = Math.sin(m.rot);
      const ax = 0.5 - ca * sep / 2, ay = 0.5 - sa * sep / 2, bx = 0.5 + ca * sep / 2, by = 0.5 + sa * sep / 2;
      ctx.globalAlpha = e1;
      circle(ctx, ax, ay, m.r); fill('form'); circle(ctx, bx, by, m.r); fill('accent');
      ctx.save(); circle(ctx, ax, ay, m.r); ctx.clip(); circle(ctx, bx, by, m.r); fill(m.mid); ctx.restore();
      ctx.globalAlpha = 1;
    } else {
      const roles = ['stroke', 'form', 'accent'];
      m.stones.forEach((s, i) => {
        const e = o.still ? 1 : easeOut(prog(t, i * 0.45, 1.0));
        ctx.save(); ctx.translate(s.cx, s.cy - (1 - e) * 0.08 - (i === 2 ? 0.006 * b : 0));
        ctx.scale(s.rx, s.ry); ctx.globalAlpha = e;
        blobPath(ctx, { ...s, cx: 0, cy: 0, asp: 1, rot: 0 }, 1, b * 0.2); fill(roles[i]);
        ctx.restore();
      });
    }
    ctx.globalAlpha = 1;
  }

  function drawAtmos(ctx, m, c, t, o, sc) {
    const b = o.still ? 0 : breathAt(t, 3.2);
    const e = (s, d) => (o.still ? 1 : easeOut(prog(t, s, d)));
    const lin = (y0, y1, stops) => { const g = ctx.createLinearGradient(0, y0, 0, y1); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); return g; };
    const rad = (x, y, r, stops) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); return g; };
    // Sky is full-bleed; the content scales about the centre.
    const sky = (y0) => { ctx.fillStyle = lin(0, 1, [[0, mix(c.tile, c.deep, 0.15)], [y0, mix(c.tile, c.accent, 0.38)], [1, mix(c.tile, c.accent, 0.2)]]); ctx.fillRect(0, 0, 1, 1); };
    const content = () => { ctx.translate(0.5, 0.5); ctx.scale(sc, sc); ctx.translate(-0.5, -0.5); };

    if (m.type === 'sunrise') {
      const rise = e(0.2, 3.2), h = m.h, sy = lerp(h + m.sr * 1.1, m.sy, rise);
      sky(h);
      content();
      ctx.fillStyle = rad(m.sx, sy, m.sr * m.glow * (1 + 0.08 * b), [[0, c.accent, 0.55 * rise], [0.45, c.accent, 0.18 * rise], [1, c.accent, 0]]);
      ctx.fillRect(-1, -1, 3, 3);
      ctx.save(); ctx.beginPath(); ctx.rect(-1, -1, 3, h + 1); ctx.clip();
      circle(ctx, m.sx, sy, m.sr); ctx.fillStyle = lin(sy - m.sr, sy + m.sr, [[0, mix(c.accent, c.light, 0.08)], [1, mix(c.accent, c.form, 0.7)]]); ctx.fill();
      ctx.restore();
      ctx.fillStyle = lin(h, 1, [[0, mix(c.form, c.deep, 0.35)], [1, mix(c.form, c.deep, 0.75)]]);
      ctx.fillRect(-1, h, 3, 2);
      ctx.fillStyle = lin(h - 0.05, h + 0.03, [[0, c.light, 0], [0.7, c.light, 0.28], [1, c.light, 0]]);
      ctx.fillRect(-1, h - 0.05, 3, 0.08);
      const re = e(2.0, 1.8);
      ctx.lineCap = 'round';
      m.bars.forEach((bar, i) => {
        const k = i / m.bars.length, y = h + 0.035 + 0.3 * Math.pow(k, 1.15) * (1 - h + 0.1);
        const shimmer = o.still ? 0 : 0.18 * Math.sin(TAU * t / 6 + bar.ph);
        const w = m.sr * 2 * (0.95 - 0.7 * k) * (1 + shimmer) * re;
        ctx.strokeStyle = css(mix(c.accent, c.light, 0.15), (0.9 - 0.55 * k) * re);
        ctx.lineWidth = 0.016 - 0.007 * k;
        ctx.beginPath(); ctx.moveTo(m.sx + bar.j - w / 2, y); ctx.lineTo(m.sx + bar.j + w / 2, y); ctx.stroke();
      });
    } else if (m.type === 'mist') {
      sky(0.6);
      content();
      const s = m.sun, se = e(0, 2.2), sy = s.y + (1 - se) * 0.08;
      ctx.fillStyle = rad(s.x, sy, s.r * 2.8 * (1 + 0.1 * b), [[0, c.accent, 0.5 * se], [1, c.accent, 0]]); ctx.fillRect(-1, -1, 3, 3);
      circle(ctx, s.x, sy, s.r); ctx.fillStyle = css(mix(c.accent, c.form, 0.12), se); ctx.fill();
      const n = m.layers.length;
      m.layers.forEach((L, i) => {
        const k = (i + 1) / n, le = e(0.3 + i * 0.35, 2.0);
        const drift = o.still ? 0 : 0.03 * Math.sin((TAU * t) / L.per + L.ph);
        const base = L.y + (1 - le) * 0.06;
        // mist pooling above the ridge
        ctx.fillStyle = lin(base - 0.12, base + 0.02, [[0, c.light, 0], [0.75, c.light, 0.32 * le], [1, c.light, 0]]);
        ctx.fillRect(-1, base - 0.12, 3, 0.14);
        const col = mix(mix(c.form, c.light, 0.5 * (1 - k)), c.deep, 0.62 * k * k);
        ctx.beginPath(); ctx.moveTo(-0.1, 1.2);
        for (let x = -0.1; x <= 1.1001; x += 0.02) {
          const y = base + L.amp * (0.65 * Math.sin(TAU * (L.f * (x + drift)) + L.ph) + 0.35 * Math.sin(TAU * (L.f2 * (x + drift)) + L.ph2));
          ctx.lineTo(x, y);
        }
        ctx.lineTo(1.1, 1.2); ctx.closePath();
        ctx.fillStyle = lin(base - L.amp, 1, [[0, col, 0.9 * le], [1, mix(col, c.deep, 0.3), le]]);
        ctx.fill();
      });
    } else if (m.type === 'halo') {
      ctx.fillStyle = rad(0.5, 0.5, 0.75, [[0, mix(c.tile, c.accent, 0.22)], [0.6, c.tile], [1, mix(c.tile, c.deep, 0.12)]]);
      ctx.fillRect(0, 0, 1, 1);
      content();
      const ge = e(0, 2), oe = e(0.2, 1.4), O = m.orb;
      ctx.fillStyle = rad(O.x, O.y, 0.44 * (1 + 0.07 * b), [[0, c.accent, 0.6 * ge], [0.5, c.accent, 0.2 * ge], [1, c.accent, 0]]); ctx.fillRect(-1, -1, 3, 3);
      circle(ctx, O.x, O.y, O.r * (0.85 + 0.15 * oe) * (1 + 0.035 * b));
      ctx.fillStyle = rad(O.x - O.r * 0.3, O.y - O.r * 0.35, O.r * 1.5, [[0, mix(c.form, c.light, 0.3), oe], [1, mix(c.form, c.deep, 0.25), oe]]); ctx.fill();
      ctx.fillStyle = css(c.stroke, 0.92);
      drawStroke(ctx, m.ring, o.still ? 1 : easeInOut(prog(t, 0.6, m.dur)));
    } else if (m.type === 'veil') {
      ctx.fillStyle = lin(0, 1, [[0, c.tile], [1, mix(c.tile, c.accent, 0.16)]]); ctx.fillRect(0, 0, 1, 1);
      content();
      const lightTile = lum(c.tile) > 0.35;
      ctx.globalCompositeOperation = lightTile ? 'multiply' : 'screen';
      const come = e(0, 2.6), sep = lerp(m.sep * 2.2, m.sep, come) * (1 + 0.16 * b);
      m.discs.forEach((d) => {
        const col = d.role === 'deep' ? (lightTile ? mix(c.stroke, c.form, 0.35) : mix(c.stroke, c.tile, 0.2)) : c[d.role];
        const x = 0.5 + d.ax * sep, y = 0.5 + d.ay * sep;
        ctx.fillStyle = rad(x, y, d.r, [[0, col, 0.82 * come], [0.84, col, 0.72 * come], [1, col, 0]]);
        circle(ctx, x, y, d.r); ctx.fill();
      });
      ctx.globalCompositeOperation = 'source-over';
    } else {
      // ripple: a moon over still water, rings opening below it
      sky(m.h);
      ctx.fillStyle = lin(m.h, 1, [[0, mix(c.form, c.deep, 0.45)], [1, mix(c.form, c.deep, 0.8)]]);
      ctx.fillRect(0, m.h, 1, 1);
      content();
      const M = m.moon, me = e(0, 2);
      ctx.fillStyle = rad(M.x, M.y, M.r * 3, [[0, c.accent, 0.45 * me], [1, c.accent, 0]]); ctx.fillRect(-1, -1, 3, 3);
      circle(ctx, M.x, M.y + (1 - me) * 0.05, M.r); ctx.fillStyle = css(mix(c.accent, c.form, 0.15), me); ctx.fill();
      const P = m.pond, re = e(1.2, 2);
      for (let i = 0; i < m.rings; i++) {
        const u = o.still ? (i + 0.5) / m.rings : ((t / m.per + i / m.rings) % 1);
        const R = 0.04 + 0.4 * u, a = Math.pow(1 - u, 1.1) * re;
        ctx.strokeStyle = css(mix(c.accent, c.light, 0.2), a);
        ctx.lineWidth = 0.016 * (1 - 0.5 * u);
        ctx.beginPath(); ctx.ellipse(P.x, P.y, R, R * 0.28, 0, 0, TAU); ctx.stroke();
      }
      ctx.beginPath(); ctx.ellipse(P.x, P.y, 0.035 * re, 0.012 * re, 0, 0, TAU); ctx.fillStyle = css(mix(c.accent, c.light, 0.3), re); ctx.fill();
    }
  }

  return { build, draw, palettes, randomSeed, normaliseSeed, contrast, mix, css, lum, BREATH, families: ['gesture', 'atmos', 'minimal'] };
})();
