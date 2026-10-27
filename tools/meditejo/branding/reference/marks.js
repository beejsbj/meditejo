/* Round 2 marks: gesture strokes that evoke a place, minimal shapes, and
 * atmospheric scenes. Every pebble, sun and disc breathes between a true
 * circle (inhale) and its organic shape (exhale), every 10 s.
 * Seeds: "g-…" gesture, "m-…" minimal, "a-…" atmospheric. */
const Marks = (() => {
  'use strict';
  const C = Core, { TAU, lerp, clamp, easeOut, easeInOut, prog, breathAt, css, mix } = C;

  // ---------- palettes ----------
  const palettes = [
    { id: 'clay', name: 'Clay', mood: 'Terracotta, ochre, cream and ink.', tile: '#F6F1E8', form: '#D2754E', stroke: '#1C1916', accent: '#D9A13F',
      ui: { light: { bg: '#FAF6EF', surface: '#F1E9DD', raised: '#EADFCF', text: '#2A221B', muted: '#7A6B5D' }, dark: { bg: '#191512', surface: '#241E19', raised: '#2E2620', text: '#F2E9DD', muted: '#A79482' } } },
    { id: 'dusk', name: 'Dusk', mood: 'Indigo, plum and a lamp of amber.', tile: '#211E45', form: '#7B4475', stroke: '#F2B65E', accent: '#E8846A',
      ui: { light: { bg: '#F6F3F8', surface: '#ECE6F1', raised: '#E2D9EA', text: '#211C3A', muted: '#6C6585' }, dark: { bg: '#12102A', surface: '#1C1938', raised: '#262247', text: '#EEE8F6', muted: '#A097BA' } } },
    { id: 'forest', name: 'Forest', mood: 'Moss on bark under morning mist.', tile: '#E8EBE2', form: '#7E8E52', stroke: '#2C241D', accent: '#C9A15A',
      ui: { light: { bg: '#F3F4EE', surface: '#E6E9DF', raised: '#DBE0D2', text: '#22271E', muted: '#687160' }, dark: { bg: '#121611', surface: '#1B211A', raised: '#252C23', text: '#E5EADE', muted: '#949E8B' } } },
    { id: 'sumi', name: 'Sumi', mood: 'Ink on paper; value carries everything.', tile: '#F3F0E9', form: '#BCB5A8', stroke: '#141413', accent: '#6E685F',
      ui: { light: { bg: '#F7F5F0', surface: '#ECE8E0', raised: '#E2DDD3', text: '#161514', muted: '#76716A' }, dark: { bg: '#111110', surface: '#1B1A19', raised: '#252422', text: '#EDEAE3', muted: '#8F8A82' } } },
    { id: 'riso', name: 'Lotus Riso', mood: 'Blush paper, lotus pink, blue ink.', tile: '#F7EAE4', form: '#EC9C8C', stroke: '#24346E', accent: '#F2C14E',
      ui: { light: { bg: '#FBF4F0', surface: '#F4E6E0', raised: '#EDDAD2', text: '#1F2647', muted: '#6E6A80' }, dark: { bg: '#121528', surface: '#1B1F38', raised: '#252A48', text: '#F4E9E4', muted: '#A39CB3' } } },
    { id: 'lagoon', name: 'Lagoon', mood: 'Night water and sand-coloured light.', tile: '#0F2D33', form: '#3F8C83', stroke: '#F1E2C2', accent: '#EE8D68',
      ui: { light: { bg: '#F1F5F3', surface: '#E3ECE9', raised: '#D5E3DF', text: '#13292C', muted: '#5F7472' }, dark: { bg: '#0B1C20', surface: '#12282D', raised: '#1A343A', text: '#E9EFEA', muted: '#8EA5A2' } } },
    { id: 'saffron', name: 'Saffron', mood: 'New. Robe saffron and maroon on temple stone.', tile: '#F2ECE1', form: '#E39A2E', stroke: '#5B1F1D', accent: '#B8452E',
      ui: { light: { bg: '#F8F4ED', surface: '#EFE7DA', raised: '#E6DBCA', text: '#3A1715', muted: '#7E655B' }, dark: { bg: '#1A1110', surface: '#251917', raised: '#30211E', text: '#F3E7DA', muted: '#AE9282' } } },
    { id: 'tide', name: 'Tidewater', mood: 'New. Sea glass, fog and slate ink, with one coral float.', tile: '#E5EAEC', form: '#86A9B1', stroke: '#1E2C3A', accent: '#DE8A62',
      ui: { light: { bg: '#F2F5F6', surface: '#E4EAEC', raised: '#D7E0E3', text: '#18242F', muted: '#5E6F7B' }, dark: { bg: '#0E151C', surface: '#162029', raised: '#1F2B36', text: '#E6EDF0', muted: '#8DA0AC' } } },
    { id: 'ember', name: 'Ember', mood: 'New. Charcoal, a banked fire and warm ash.', tile: '#1D1715', form: '#8E3E28', stroke: '#F1C886', accent: '#E8692F',
      ui: { light: { bg: '#F7F2EE', surface: '#EEE5DE', raised: '#E4D8CE', text: '#2A1C17', muted: '#7C675D' }, dark: { bg: '#141010', surface: '#1F1918', raised: '#2A2220', text: '#F2E6DA', muted: '#A8968A' } } },
  ];
  const PAL = Object.fromEntries(palettes.map((p) => [p.id, p]));

  // ---------- seeds and days ----------
  const FAMILY = { g: 'gesture', a: 'atmos', m: 'minimal' };
  const PREFIX = { gesture: 'g', atmos: 'a', minimal: 'm' };
  const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
  function randomSeed(family) { let s = ''; for (let i = 0; i < 4; i++) s += ALPHABET[Math.floor(Math.random() * ALPHABET.length)]; return PREFIX[family] + '-' + s; }
  function normaliseSeed(input) { const s = String(input).trim().toLowerCase().replace(/\s+/g, '-'); return /^[gam]-[a-z0-9-]+$/.test(s) ? s : 'g-' + (s || '0'); }
  const dayKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const dayNumber = (d) => Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 864e5);
  // The local day picks the family, then the date itself is the seed.
  function daily(d) {
    const key = dayKey(d), rng = C.makeRng('day:' + key);
    const fam = rng.weighted({ gesture: 0.45, minimal: 0.4, atmos: 0.15 });
    // One fixed shuffle, walked a day at a time: no palette repeats within
    // nine days, and every day knows its palette without any stored state.
    const n = dayNumber(d), P = palettes.length, order = palettes.map((p, i) => i), pr = C.makeRng('palette-order');
    for (let i = P - 1; i > 0; i--) { const j = Math.floor(pr.next() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
    return { seed: `${PREFIX[fam]}-${key}`, pal: palettes[order[n % P]].id, key };
  }

  // ---------- gesture ----------
  // Each kind returns a centreline in tile units and places its pebble so the
  // two read as a place together: a sun in a doorway, a sitter on a cushion.
  const GESTURE = {
    doorway(r) {
      const W = r.range(0.34, 0.42), yb = r.range(0.76, 0.8), yt = yb - r.range(0.5, 0.56), x0 = 0.5 - W / 2 + r.range(-0.02, 0.02), x1 = x0 + W, ys = yt + W / 2;
      const p = C.pen(x0 - r.range(0.05, 0.09), yb + 0.004).quad(x0 - 0.01, yb, x0, yb - 0.04).line(x0, ys).arc(x0 + W / 2, ys, W / 2, W / 2 * r.range(1, 1.12), Math.PI, TAU).line(x1, yb - 0.03).quad(x1 + 0.005, yb, x1 + r.range(0.08, 0.13), yb - r.range(0, 0.02));
      return { pts: p.pts, blob: [x0 + W * r.range(0.45, 0.7), ys + r.range(0.0, 0.08), r.range(0.15, 0.19)], taper: 'marker' };
    },
    // A seat line: the pebble rests on it and presses a soft hollow.
    cushion(r) {
      const y0 = r.range(0.66, 0.72), cx = 0.5 + r.range(-0.06, 0.06), R = r.range(0.17, 0.21), dip = r.range(0.025, 0.04), lift = r.range(0.01, 0.03), out = [];
      for (let i = 0; i <= 400; i++) { const u = i / 400, x = lerp(0.13, 0.87, u), k = (x - cx) / (R * 0.9); out.push([x, y0 + dip * Math.exp(-k * k) - lift * Math.pow(Math.abs(u - 0.5) * 2, 3)]); }
      return { pts: out, blob: [cx, y0 + dip * 0.7 - R * 0.98, R], taper: 'swell' };
    },
    // A horizon with one cursive loop in it: a pause on the way.
    horizon(r) {
      const yh = r.range(0.6, 0.66), lx = r.range(0.56, 0.68), a = r.range(0.04, 0.055), b = r.range(0.055, 0.07), h = r.range(0.14, 0.18);
      const p = C.pen(0.12, yh + r.range(-0.01, 0.01)).quad(0.3, yh + 0.008, lx - a, yh);
      for (let i = 1; i <= 140; i++) { const t = (i / 140) * TAU; p.pts.push([lx - a + 2 * a * (t / TAU) + b * Math.sin(t), yh - h * (1 - Math.cos(t)) / 2]); }
      p.quad(lx + a + 0.12, yh + 0.006, 0.88, yh - r.range(0, 0.025));
      const R = r.range(0.17, 0.22);
      return { pts: p.pts, blob: [r.range(0.34, 0.46), yh - R * r.range(0.35, 0.7), R], taper: 'marker' };
    },
    hearth(r) {
      const bx = r.range(0.24, 0.3), y = r.range(0.74, 0.78), sx = r.range(0.48, 0.54), sway = r.range(0.06, 0.1), top = r.range(0.24, 0.3), cr = r.range(0.04, 0.055);
      const p = C.pen(bx, y).line(sx - 0.04, y).quad(sx, y, sx, y - 0.06).cubic(sx + sway, y - 0.18, sx - sway, top + 0.16, sx + 0.01, top + cr * 2);
      const c0x = sx + 0.01 + cr, c0y = top + cr * 2;
      p.arc(c0x, c0y, cr, cr, Math.PI, Math.PI + TAU * 0.85, 70);
      return { pts: p.pts, blob: [sx + r.range(-0.03, 0.03), r.range(0.52, 0.58), r.range(0.19, 0.23)], taper: 'fade' };
    },
    path(r) {
      const ex = r.range(0.56, 0.66), ey = r.range(0.34, 0.42), lr = r.range(0.035, 0.045);
      const p = C.pen(r.range(0.14, 0.2), r.range(0.84, 0.88)).cubic(0.5, 0.86, 0.22, r.range(0.62, 0.68), 0.5, r.range(0.56, 0.6)).cubic(0.72, 0.52, ex - 0.12, ey + 0.16, ex, ey + lr);
      p.arc(ex, ey, lr, lr, Math.PI / 2, Math.PI / 2 + TAU * 1.05, 70);
      return { pts: p.pts, blob: [ex + r.range(-0.04, 0.02), ey + r.range(0.02, 0.06), r.range(0.15, 0.19)], taper: 'marker' };
    },
    shelter(r) {
      const ay = r.range(0.22, 0.28), ey = r.range(0.56, 0.62), w = r.range(0.33, 0.38), ax = 0.5 + r.range(-0.02, 0.02);
      const p = C.pen(ax - w - 0.03, ey + 0.03).quad(ax - w + 0.01, ey + 0.005, ax - w * 0.55, ey - (ey - ay) * 0.5).quad(ax - 0.03, ay - 0.005, ax, ay).quad(ax + 0.03, ay - 0.005, ax + w * 0.55, ey - (ey - ay) * 0.5).quad(ax + w - 0.01, ey + 0.005, ax + w + 0.04, ey + 0.035);
      const R = r.range(0.16, 0.2);
      return { pts: p.pts, blob: [ax + r.range(-0.04, 0.04), ey + R * 0.25, R], taper: 'marker' };
    },
    window(r) {
      const w = r.range(0.36, 0.42), h = r.range(0.4, 0.46), x0 = 0.5 - w / 2 + r.range(-0.03, 0.01), y0 = 0.5 - h / 2 + r.range(-0.02, 0.02), k = 0.06;
      const p = C.pen(x0 + k, y0).line(x0 + w - k, y0).quad(x0 + w, y0, x0 + w, y0 + k).line(x0 + w, y0 + h - k).quad(x0 + w, y0 + h, x0 + w - k, y0 + h).line(x0 + k, y0 + h).quad(x0, y0 + h, x0, y0 + h - k).line(x0, y0 + k).quad(x0, y0, x0 + k, y0).line(x0 + k + r.range(0.08, 0.16), y0 - 0.004);
      return { pts: p.pts, blob: [x0 + w * r.range(0.62, 0.85), y0 + h * r.range(0.2, 0.4), r.range(0.15, 0.2)], taper: 'marker' };
    },
    step(r) {
      const y1 = r.range(0.7, 0.74), y2 = y1 - r.range(0.12, 0.16), sx = r.range(0.44, 0.52);
      const p = C.pen(0.13, y1).line(sx - 0.05, y1).quad(sx, y1, sx, y1 - 0.05).line(sx, y2 + 0.04).quad(sx, y2, sx + 0.05, y2).line(0.87, y2 - r.range(0, 0.02));
      const R = r.range(0.14, 0.18);
      return { pts: p.pts, blob: [sx + r.range(0.12, 0.2), y2 - R * 0.95, R], taper: 'marker' };
    },
    // Round 1's kinds stay in the pool, quietly.
    loops(r) {
      const n = r.pick([1, 2]), d = r.range(2.3, 3.2), h = r.range(4.4, 5.8), lead = r.range(2.2, 3.4), exit = r.range(2.4, 3.6), lift = r.range(1.2, 3.4), out = [];
      const t0 = -lead, t1 = TAU * n + exit;
      for (let i = 0; i <= 700; i++) { const t = lerp(t0, t1, i / 700), env = C.ss(t0 + 0.4, 0.4, t) * (1 - C.ss(TAU * n - 0.3, TAU * n + 1.4, t)); out.push([t + d * env * Math.sin(t), -h * env * (1 - Math.cos(t)) / 2 - lift * Math.pow(C.ss(TAU * n - 0.6, t1, t), 1.6)]); }
      const R = r.range(0.25, 0.3);
      return { pts: fit(out, 0.74, 0.5, r.range(0.54, 0.6)), blob: [0.5 + r.range(-0.05, 0.05), 0.5, R], taper: 'marker' };
    },
    enso(r) {
      const th0 = r.range(0, TAU), sw = r.range(1.68, 1.9) * Math.PI, dir = r.sign(), out = [];
      for (let i = 0; i <= 500; i++) { const u = i / 500, th = th0 + dir * sw * u, rr = 0.29 * (1 - 0.07 * u); out.push([0.5 + rr * Math.cos(th), 0.5 + rr * Math.sin(th)]); }
      return { pts: out, blob: [0.5 + r.range(-0.05, 0.05), 0.5 + r.range(-0.05, 0.05), r.range(0.19, 0.23)], taper: 'brush' };
    },
    wave(r) {
      const cyc = r.range(1, 1.5), A = r.range(0.06, 0.09), out = [];
      for (let i = 0; i <= 500; i++) { const u = i / 500, env = Math.pow(Math.sin(Math.PI * (0.06 + 0.88 * u)), 0.6); out.push([lerp(0.14, 0.86, u), 0.58 - A * env * Math.sin(TAU * cyc * u)]); }
      return { pts: out, blob: [0.5 + r.range(-0.06, 0.06), 0.5, r.range(0.22, 0.27)], taper: 'swell' };
    },
  };
  function fit(raw, width, cx, cy) {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const [x, y] of raw) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    const s = width / (x1 - x0);
    return raw.map(([x, y]) => [cx + (x - (x0 + x1) / 2) * s, cy + (y - (y0 + y1) / 2) * s]);
  }
  const GESTURE_WEIGHT = { doorway: 3, cushion: 3, horizon: 3, hearth: 3, path: 3, shelter: 3, window: 2.5, step: 0.6, enso: 1, wave: 1, loops: 0.6 };
  const GESTURE_LABEL = { doorway: 'doorway', cushion: 'cushion', horizon: 'horizon', hearth: 'hearth', path: 'path home', shelter: 'shelter', window: 'window', step: 'threshold', loops: 'loops (round 1)', enso: 'ensō', wave: 'breath wave' };

  function buildGesture(r, type) {
    type = type || r.weighted(GESTURE_WEIGHT);
    const g = GESTURE[type](r);
    const pts = C.jitterPts(g.pts, r, 0.006);
    const width = r.range(0.036, 0.046) * (g.taper === 'brush' ? 1.35 : 1);
    const stroke = C.makeStroke(pts, { taper: g.taper, width, wobble: 0.003, pressure: 0.12, nib: r.chance(0.35) ? 0.2 : 0 }, r);
    const [bx, by, R] = g.blob;
    const blob = C.makeBlob(r, bx, by, R, r.range(0.9, 1.4), 0.004);
    let maxd = Math.hypot(bx - 0.5, by - 0.5) + R * 1.15;
    for (let i = 0; i < stroke.n; i++) maxd = Math.max(maxd, Math.hypot(stroke.x[i] - 0.5, stroke.y[i] - 0.5) + stroke.w[i] / 2);
    return { type, label: GESTURE_LABEL[type], stroke, blob, fit: Math.min(1, 0.44 / maxd), dur: clamp(1.4 + 0.9 * stroke.len, 2.2, 3.6) };
  }
  function drawGesture(ctx, m, c, t, o) {
    const s0 = 0.5, bStart = s0 + m.dur + 0.4, b = o.still ? 0 : breathAt(t, bStart);
    const appear = easeOut(prog(t, 0, 1));
    ctx.globalAlpha = appear;
    C.blobPath(ctx, m.blob, { grow: (0.92 + 0.08 * appear) * (1 + 0.025 * b), imperf: 1 - b });
    ctx.fillStyle = css(c.form); ctx.fill();
    ctx.globalAlpha = 1;
    ctx.fillStyle = css(c.stroke);
    C.drawStroke(ctx, m.stroke, o.still ? 1 : easeInOut(prog(t, s0, m.dur)));
  }

  // ---------- minimal ----------
  const MIN_WEIGHT = { split: 1, arch: 1, pebble: 1, crescent: 1, vesica: 1, cairn: 0.7, window: 1.2, hearth: 1.2, clearing: 1.2, cushion: 1.4, shelter: 1.2 };
  const MIN_LABEL = { split: 'split sun', arch: 'arch', pebble: 'pebble & bindu', crescent: 'crescent', vesica: 'vesica', cairn: 'cairn', window: 'window', hearth: 'hearth', clearing: 'clearing', cushion: 'cushion', shelter: 'shelter' };
  function buildMinimal(r, type) {
    type = type || r.weighted(MIN_WEIGHT);
    const m = { type, label: MIN_LABEL[type], fit: 1 };
    const rough = r.range(0.5, 0.9), B = (x, y, R) => C.makeBlob(r, x, y, R, rough, 0.003);
    m.roles = r.pick([['form', 'stroke', 'accent'], ['form', 'accent', 'stroke'], ['accent', 'stroke', 'form'], ['form', 'stroke', 'stroke']]);
    switch (type) {
      case 'split': { const R = r.range(0.27, 0.31); m.disc = B(0.5, 0.5, R); m.h = 0.5 + R * r.range(0.05, 0.38); m.gap = r.range(0.024, 0.034); m.shift = r.range(-0.03, 0.03); break; }
      case 'arch': m.w = r.range(0.38, 0.46); m.ht = r.range(0.54, 0.62); m.sun = B(0.5, 0, r.range(0.09, 0.12)); m.sunY = r.range(0, 0.3); break;
      case 'pebble': { m.peb = B(0.5 + r.range(-0.05, 0.05), 0.5 + r.range(-0.04, 0.04), r.range(0.25, 0.3)); const a = r.range(0, TAU), d = r.range(0.25, 0.6); m.dot = B(m.peb.cx + Math.cos(a) * m.peb.R * d, m.peb.cy + Math.sin(a) * m.peb.R * d, r.range(0.045, 0.065)); m.second = r.chance(0.5) ? B(m.peb.cx - Math.cos(a) * m.peb.R * 0.85, m.peb.cy - Math.sin(a) * m.peb.R * 0.85, r.range(0.09, 0.13)) : null; break; }
      case 'crescent': { m.disc = B(0.5, 0.5, r.range(0.26, 0.3)); const a = r.range(-2.6, -0.5) + (r.chance(0.5) ? Math.PI : 0); m.cut = { ax: Math.cos(a), ay: Math.sin(a), d: r.range(0.13, 0.2) }; m.dot = r.chance(0.7) ? r.range(0.035, 0.05) : 0; break; }
      case 'vesica': m.a = B(0, 0.5, r.range(0.2, 0.24)); m.b = B(0, 0.5, m.a.R); m.sep = r.range(0.17, 0.24); break;
      case 'cairn': { let y = 0.8; m.stones = [r.range(0.2, 0.24), r.range(0.14, 0.17), r.range(0.08, 0.11)].map((rx) => { const ry = rx * r.range(0.5, 0.62); y -= ry; const s = B(0.5 + r.range(-0.03, 0.03), y, 1); s.rot = 0; s.rx = rx; s.ry = ry; y -= ry * 0.92; return s; }); const shift = (1 - (0.8 - y)) / 2 - y; m.stones.forEach((s) => (s.cy += shift)); break; }
      case 'window': m.w = r.range(0.4, 0.48); m.h = r.range(0.46, 0.54); m.rad = r.range(0.04, 0.1); m.sun = B(0.5 + r.range(-0.08, 0.08), 0.5 + r.range(-0.12, 0.02), r.range(0.1, 0.14)); m.mullion = r.chance(0.6); break;
      case 'hearth': m.base = B(0.5, 0.66, r.range(0.24, 0.28)); m.flame = r.range(0.1, 0.13); m.fy = r.range(0.44, 0.5); break;
      case 'clearing': m.ring = B(0.5, 0.5, r.range(0.28, 0.32)); m.inner = r.range(0.55, 0.68); m.dot = B(0.5 + r.range(-0.05, 0.05), 0.5 + r.range(-0.05, 0.05), r.range(0.05, 0.075)); break;
      case 'cushion': m.cushion = B(0.5, r.range(0.68, 0.72), 1); m.cushion.rot = 0; m.cushion.rx = r.range(0.24, 0.3); m.cushion.ry = r.range(0.07, 0.09); m.sitter = B(0.5 + r.range(-0.02, 0.02), 0, r.range(0.15, 0.19)); m.sitter.cy = m.cushion.cy - m.cushion.ry - m.sitter.R * 0.85; break;
      case 'shelter': m.ay = r.range(0.2, 0.26); m.ey = r.range(0.48, 0.54); m.w = r.range(0.32, 0.38); m.sitter = B(0.5, 0, r.range(0.14, 0.18)); m.sitter.cy = m.ey + m.sitter.R * 0.95; break;
    }
    return m;
  }
  function drawMinimal(ctx, m, c, t, o) {
    const b = o.still ? 0 : breathAt(t, 2.4), imp = 1 - b;
    const e1 = o.still ? 1 : easeOut(prog(t, 0, 1.1)), e2 = o.still ? 1 : easeOut(prog(t, 0.6, 1.3)), e3 = o.still ? 1 : easeOut(prog(t, 1.1, 1.2));
    const [r1, r2, r3] = m.roles;
    const fill = (role, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = css(c[role]); ctx.fill(); ctx.globalAlpha = 1; };
    const blob = (bb, opt) => C.blobPath(ctx, bb, { imperf: imp, ...opt });
    switch (m.type) {
      case 'split': {
        ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 1, m.h - m.gap / 2); ctx.clip(); blob(m.disc, { grow: 1 + 0.02 * b, dy: (1 - e1) * 0.12 }); fill(r1); ctx.restore();
        ctx.save(); ctx.beginPath(); ctx.rect(0, m.h + m.gap / 2, 1, 1); ctx.clip(); blob(m.disc, { dx: m.shift * e2 }); fill(r2, e2); ctx.restore(); break;
      }
      case 'arch': {
        const w = m.w, top = 0.5 - m.ht / 2, bot = 0.5 + m.ht / 2, x0 = 0.5 - w / 2, ys = top + w / 2;
        const arch = () => { ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0, ys); ctx.arc(0.5, ys, w / 2, Math.PI, 0); ctx.lineTo(x0 + w, bot); ctx.closePath(); };
        ctx.save(); ctx.beginPath(); ctx.rect(0, lerp(bot, top, e1) - 0.01, 1, 1); ctx.clip(); arch(); fill(r1); ctx.restore();
        ctx.save(); arch(); ctx.clip(); blob(m.sun, { dy: lerp(bot + 0.1, ys + m.ht * m.sunY, e2) - 0.008 * b }); fill(r2 === 'stroke' ? 'tile' : r2); ctx.restore(); break;
      }
      case 'pebble': {
        blob(m.peb, { grow: (0.92 + 0.08 * e1) * (1 + 0.02 * b) }); fill(r1, e1);
        if (m.second) { blob(m.second, { grow: 0.6 + 0.4 * e3 }); fill(r3 === r1 ? 'accent' : r3, e3); }
        blob(m.dot, { grow: e2, dy: -(1 - e2) * 0.08 }); fill(r2 === r1 ? 'stroke' : r2); break;
      }
      case 'crescent': {
        const d = lerp(0.62, m.cut.d, e2) * (1 + 0.05 * b);
        ctx.save(); blob(m.disc, { grow: 0.92 + 0.08 * e1 }); ctx.clip();
        ctx.beginPath(); ctx.rect(-1, -1, 3, 3); ctx.arc(0.5 + m.cut.ax * d, 0.5 + m.cut.ay * d, m.disc.R * 1.02, 0, TAU); ctx.globalAlpha = e1; ctx.fillStyle = css(c[r1]); ctx.fill('evenodd'); ctx.restore(); ctx.globalAlpha = 1;
        if (m.dot) { C.circle(ctx, 0.5 + m.cut.ax * m.disc.R * 0.62, 0.5 + m.cut.ay * m.disc.R * 0.62, m.dot * e3); fill('accent'); } break;
      }
      case 'vesica': {
        const sep = lerp(m.sep * 2.4, m.sep, e1) * (1 - 0.1 * b);
        m.a.cx = 0.5 - sep / 2; m.b.cx = 0.5 + sep / 2;
        blob(m.a); fill('form', e1); blob(m.b); fill('accent', e1);
        ctx.save(); blob(m.a); ctx.clip(); blob(m.b); fill(r2 === 'form' || r2 === 'accent' ? 'stroke' : r2, e1); ctx.restore(); break;
      }
      case 'cairn': {
        ['stroke', 'form', 'accent'].forEach((role, i) => { const s = m.stones[i], e = o.still ? 1 : easeOut(prog(t, i * 0.45, 1)); blob(s, { sx: s.rx, sy: s.ry, dy: -(1 - e) * 0.08 - (i === 2 ? 0.006 * b : 0) }); fill(role, e); }); break;
      }
      case 'window': {
        const x0 = 0.5 - m.w / 2, y0 = 0.5 - m.h / 2;
        const rr = () => { ctx.beginPath(); ctx.roundRect(x0, lerp(y0 + m.h, y0, e1), m.w, m.h * e1, m.rad); };
        rr(); fill(r1);
        ctx.save(); rr(); ctx.clip(); blob(m.sun, { dy: (1 - e2) * 0.2 - 0.01 * b, grow: 1 + 0.03 * b }); fill(r1 === 'accent' ? 'form' : 'accent');
        if (m.mullion) { ctx.fillStyle = css(c.tile); ctx.fillRect(0.5 - 0.012, y0, 0.024, m.h); ctx.fillRect(x0, 0.5 - 0.012, m.w, 0.024); }
        ctx.restore(); break;
      }
      case 'hearth': {
        ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 1, m.base.cy); ctx.clip(); blob(m.base, { grow: 0.9 + 0.1 * e1 }); fill(r1 === 'accent' ? 'form' : r1); ctx.restore();
        const fh = m.flame * (1 + 0.08 * b) * e2, fx = 0.5, fy = m.fy + (1 - e2) * 0.1;
        ctx.beginPath(); ctx.moveTo(fx, fy - fh * 1.9); ctx.bezierCurveTo(fx + fh * 1.1, fy - fh * 0.6, fx + fh * 0.9, fy + fh, fx, fy + fh); ctx.bezierCurveTo(fx - fh * 0.9, fy + fh, fx - fh * 1.1, fy - fh * 0.6, fx, fy - fh * 1.9); fill('accent');
        ctx.fillStyle = css(c.stroke); ctx.fillRect(0.5 - m.base.R * 1.05, m.base.cy, m.base.R * 2.1 * e3, 0.03); break;
      }
      case 'clearing': {
        ctx.save(); blob(m.ring, { grow: (0.9 + 0.1 * e1) * (1 + 0.02 * b) }); C.blobPath(ctx, m.ring, { grow: m.inner * (1 - 0.04 * b), imperf: imp * 0.6, keep: true }); ctx.fillStyle = css(c[r1]); ctx.globalAlpha = e1; ctx.fill('evenodd'); ctx.restore(); ctx.globalAlpha = 1;
        blob(m.dot, { grow: e2 }); fill(r2 === r1 ? 'stroke' : r2); break;
      }
      case 'cushion': {
        const cu = m.cushion; blob(cu, { sx: cu.rx * (0.9 + 0.1 * e1), sy: cu.ry }); fill(r2 === 'stroke' ? 'stroke' : r1 === 'stroke' ? 'form' : 'stroke');
        blob(m.sitter, { dy: -(1 - e2) * 0.1 - 0.008 * b, grow: 1 + 0.02 * b }); fill(r1 === 'stroke' ? 'accent' : r1, e2); break;
      }
      case 'shelter': {
        const ax = 0.5, w = m.w * (0.85 + 0.15 * e1);
        ctx.beginPath(); ctx.moveTo(ax - w, m.ey); ctx.quadraticCurveTo(ax - w * 0.35, m.ay + 0.04, ax, m.ay); ctx.quadraticCurveTo(ax + w * 0.35, m.ay + 0.04, ax + w, m.ey); ctx.lineTo(ax + w - 0.05, m.ey); ctx.quadraticCurveTo(ax + w * 0.3, m.ay + 0.1, ax, m.ay + 0.07); ctx.quadraticCurveTo(ax - w * 0.3, m.ay + 0.1, ax - w + 0.05, m.ey); ctx.closePath(); fill('stroke');
        blob(m.sitter, { grow: e2 * (1 + 0.02 * b) }); fill(r1 === 'stroke' ? 'form' : r1); break;
      }
    }
  }

  // ---------- atmospheric ----------
  // Printed, not rendered: flat inks laid in two misregistered plates, soft
  // light from a single source, then paper tooth and ink speckle on top.
  const ATMOS = ['dawn', 'ridges', 'moonpool', 'doorlight', 'halo', 'shoreline'];
  function buildAtmos(r, type) {
    type = type || r.pick(ATMOS);
    const m = { type, label: { dawn: 'dawn over water', ridges: 'ridges in mist', moonpool: 'moon pool', doorlight: 'lit doorway', halo: 'halo', shoreline: 'shoreline' }[type], fit: 1 };
    m.mis = [r.range(-0.008, 0.008), r.range(0.003, 0.009)];
    m.sun = C.makeBlob(r, 0.5 + r.range(-0.1, 0.1), r.range(0.3, 0.42), r.range(0.13, 0.18), 0.45, 0.003);
    m.h = r.range(0.58, 0.66);
    m.layers = Array.from({ length: r.int(3, 4) }, (_, i) => ({ y: lerp(0.52, 0.8, i / 3) + r.range(-0.02, 0.02), amp: r.range(0.02, 0.05), f: r.range(0.6, 1.4), ph: r.range(0, TAU), f2: r.range(1.8, 2.8), ph2: r.range(0, TAU), per: r.range(26, 40) }));
    m.door = { w: r.range(0.24, 0.3), h: r.range(0.42, 0.5) };
    if (type === 'halo') { const raw = []; const th0 = r.range(0, TAU), sw = r.range(1.7, 1.88) * Math.PI; for (let i = 0; i <= 400; i++) { const u = i / 400, th = th0 + sw * u, rr = r.range(0.295, 0.3) * (1 - 0.06 * u); raw.push([0.5 + rr * Math.cos(th), 0.5 + rr * Math.sin(th)]); } m.ring = C.makeStroke(raw, { taper: 'brush', width: 0.034, wobble: 0.003, pressure: 0.12 }, r); m.sun.cx = 0.5; m.sun.cy = 0.5; m.sun.R *= 1.15; }
    if (type === 'moonpool' || type === 'shoreline') m.sun.cy = r.range(0.24, 0.3);
    return m;
  }
  function drawAtmos(ctx, m, c, t, o) {
    const b = o.still ? 0 : breathAt(t, 3.2), imp = 1 - b, e = (s, d) => (o.still ? 1 : easeOut(prog(t, s, d)));
    const lin = (y0, y1, stops) => { const g = ctx.createLinearGradient(0, y0, 0, y1); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); return g; };
    const glow = (x, y, r, col, a) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(0.5, css(col, a * 0.35)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.fillRect(0, 0, 1, 1); };
    const plateB = (fn) => { ctx.save(); ctx.translate(m.mis[0], m.mis[1]); ctx.globalCompositeOperation = C.overprint(c); fn(); ctx.restore(); };
    const sky = mix(c.tile, c.accent, c.lightPaper ? 0.18 : 0.12);
    ctx.fillStyle = lin(0, 1, [[0, mix(c.tile, c.deep, c.lightPaper ? 0.06 : 0)], [0.6, sky], [1, mix(c.tile, c.form, 0.25)]]); ctx.fillRect(0, 0, 1, 1);
    const S = m.sun, rise = e(0.2, 3), sunDy = (1 - rise) * 0.25;
    const ridge = (L, i, n, drift) => {
      const k = (i + 1) / n, base = L.y + (1 - e(0.3 + i * 0.3, 2)) * 0.06;
      ctx.beginPath(); ctx.moveTo(-0.1, 1.2);
      for (let x = -0.1; x <= 1.1001; x += 0.02) ctx.lineTo(x, base + L.amp * (0.65 * Math.sin(TAU * L.f * (x + drift) + L.ph) + 0.35 * Math.sin(TAU * L.f2 * (x + drift) + L.ph2)));
      ctx.lineTo(1.1, 1.2); ctx.closePath();
      ctx.fillStyle = css(mix(mix(c.form, c.light, 0.45 * (1 - k)), c.deep, 0.6 * k * k)); ctx.fill();
    };
    switch (m.type) {
      case 'dawn': case 'ridges': {
        glow(S.cx, S.cy + sunDy, S.R * 3.2 * (1 + 0.08 * b), c.accent, 0.55 * rise);
        plateB(() => { C.blobPath(ctx, S, { imperf: imp, dy: sunDy }); ctx.fillStyle = css(c.accent); ctx.fill(); });
        if (m.type === 'ridges') { m.layers.forEach((L, i) => { const drift = o.still ? 0 : 0.025 * Math.sin((TAU * t) / L.per + L.ph); ctx.fillStyle = lin(L.y - 0.1, L.y + 0.02, [[0, c.light, 0], [0.8, c.light, c.lightPaper ? 0.4 : 0.18], [1, c.light, 0]]); ctx.fillRect(0, L.y - 0.1, 1, 0.12); ridge(L, i, m.layers.length, drift); }); }
        else {
          ctx.fillStyle = css(mix(c.form, c.deep, 0.45)); ctx.fillRect(0, m.h, 1, 1);
          plateB(() => { ctx.fillStyle = css(mix(c.form, c.deep, 0.15)); ctx.fillRect(0, m.h + 0.004, 1, 1); });
          const re = e(1.8, 1.6); ctx.lineCap = 'round';
          for (let i = 0; i < 6; i++) { const k = i / 6, y = m.h + 0.035 + 0.27 * Math.pow(k, 1.2), sh = o.still ? 0 : 0.2 * Math.sin(TAU * t / 6 + i * 1.7); const w = S.R * 2 * (0.9 - 0.65 * k) * (1 + sh) * re; ctx.strokeStyle = css(c.accent, (0.95 - 0.5 * k) * re); ctx.lineWidth = 0.017 - 0.008 * k; ctx.beginPath(); ctx.moveTo(S.cx - w / 2, y); ctx.lineTo(S.cx + w / 2, y); ctx.stroke(); }
        }
        break;
      }
      case 'moonpool': case 'shoreline': {
        glow(S.cx, S.cy, S.R * 3, c.accent, 0.45 * rise);
        plateB(() => { C.blobPath(ctx, S, { imperf: imp, dy: sunDy * 0.5 }); ctx.fillStyle = css(mix(c.accent, c.light, 0.2)); ctx.fill(); });
        ctx.fillStyle = lin(m.h, 1, [[0, mix(c.form, c.deep, 0.35)], [1, mix(c.form, c.deep, 0.75)]]); ctx.fillRect(0, m.h, 1, 1);
        if (m.type === 'moonpool') {
          for (let i = 0; i < 4; i++) { const u = o.still ? (i + 0.5) / 4 : ((t / 10 + i / 4) % 1), R = 0.04 + 0.42 * u; ctx.strokeStyle = css(mix(c.accent, c.light, 0.3), Math.pow(1 - u, 1.1) * e(1, 2)); ctx.lineWidth = 0.014 * (1 - 0.5 * u); ctx.beginPath(); ctx.ellipse(S.cx, m.h + 0.18, R, R * 0.26, 0, 0, TAU); ctx.stroke(); }
        } else {
          for (let i = 0; i < 4; i++) { const y = m.h + 0.06 + i * 0.075, ph = o.still ? 0 : t * 0.25 + i; ctx.beginPath(); ctx.moveTo(0, y); for (let x = 0; x <= 1.001; x += 0.02) ctx.lineTo(x, y + 0.012 * Math.sin(TAU * (x * (1.4 + i * 0.3)) + ph)); ctx.lineTo(1, 1); ctx.lineTo(0, 1); ctx.closePath(); ctx.fillStyle = css(mix(c.form, c.deep, 0.2 + i * 0.18), 0.85); ctx.fill(); ctx.strokeStyle = css(c.light, 0.35 * (1 - i / 4)); ctx.lineWidth = 0.006; ctx.stroke(); }
        }
        break;
      }
      case 'doorlight': {
        ctx.fillStyle = css(mix(c.deep, c.form, 0.25)); ctx.fillRect(0, 0, 1, 1);
        const D = m.door, x0 = 0.5 - D.w / 2, bot = 0.8, top = bot - D.h, ys = top + D.w / 2, open = e(0.2, 2.4);
        const arch = () => { ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0, ys); ctx.arc(0.5, ys, D.w / 2, Math.PI, 0); ctx.lineTo(x0 + D.w, bot); ctx.closePath(); };
        ctx.save(); arch(); ctx.clip(); ctx.fillStyle = lin(top, bot, [[0, mix(c.tile, c.accent, 0.3)], [1, mix(c.accent, c.form, 0.3)]]); ctx.fillRect(0, 0, 1, 1);
        C.blobPath(ctx, S, { imperf: imp, dx: 0.5 - S.cx, dy: ys + 0.06 - S.cy + sunDy, grow: 0.55 }); ctx.fillStyle = css(c.accent); ctx.fill(); ctx.restore();
        // light falling on the floor
        ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0 + D.w, bot); ctx.lineTo(0.5 + D.w * 1.4, 1.02); ctx.lineTo(0.5 - D.w * 1.1, 1.02); ctx.closePath();
        const g = ctx.createLinearGradient(0, bot, 0, 1); g.addColorStop(0, css(mix(c.accent, c.tile, 0.4), 0.7 * open * (0.9 + 0.1 * b))); g.addColorStop(1, css(c.accent, 0)); ctx.fillStyle = g; ctx.fill();
        plateB(() => { ctx.lineWidth = 0.012; ctx.strokeStyle = css(mix(c.accent, c.light, 0.4), 0.7); arch(); ctx.stroke(); });
        break;
      }
      case 'halo': {
        ctx.fillStyle = css(mix(c.tile, c.deep, c.lightPaper ? 0.04 : 0)); ctx.fillRect(0, 0, 1, 1);
        glow(0.5, 0.5, 0.46 * (1 + 0.06 * b), c.accent, 0.55 * rise);
        plateB(() => { C.blobPath(ctx, S, { imperf: imp, grow: (0.9 + 0.1 * rise) * (1 + 0.03 * b) }); ctx.fillStyle = css(c.form); ctx.fill(); });
        ctx.fillStyle = css(c.stroke, 0.92); C.drawStroke(ctx, m.ring, o.still ? 1 : easeInOut(prog(t, 0.6, 2.6)));
        break;
      }
    }
  }

  // ---------- build and draw ----------
  function build(seedInput, type) {
    const seed = normaliseSeed(seedInput), family = FAMILY[seed[0]], r = C.makeRng('r2:' + seed);
    const m = family === 'gesture' ? buildGesture(r, type) : family === 'atmos' ? buildAtmos(r, type) : buildMinimal(r, type);
    m.seed = seed; m.family = family;
    return m;
  }
  // o: still, bg (false = no tile), scale, colors (role overrides), px, dpr
  function draw(ctx, m, pal, t, o = {}) {
    if (o.still) t = 60;
    const c = C.roles(pal, o.colors);
    if (m.family === 'atmos') {
      ctx.save(); ctx.translate(0.5, 0.5); ctx.scale(o.scale || 1, o.scale || 1); ctx.translate(-0.5, -0.5);
      drawAtmos(ctx, m, c, t, o); ctx.restore();
      C.finish(ctx, c, o.px || 256, { dpr: o.dpr, speckle: 0.3 });
      return;
    }
    if (o.bg !== false) { ctx.fillStyle = css(c.tile); ctx.fillRect(0, 0, 1, 1); }
    const sc = (o.scale || 1) * m.fit;
    ctx.save(); ctx.translate(0.5, 0.5); ctx.scale(sc, sc); ctx.translate(-0.5, -0.5);
    if (m.family === 'gesture') drawGesture(ctx, m, c, t, o); else drawMinimal(ctx, m, c, t, o);
    ctx.restore();
    if (o.bg !== false && o.finish !== false) C.finish(ctx, c, o.px || 256, { dpr: o.dpr, paper: 0.1, speckle: 0.18, vignette: 0 });
  }

  return { palettes, PAL, build, draw, randomSeed, normaliseSeed, daily, dayKey, GESTURE_WEIGHT, MIN_WEIGHT, ATMOS, families: ['gesture', 'minimal', 'atmos'] };
})();
