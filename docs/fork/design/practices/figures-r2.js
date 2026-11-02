/* Practice figures, round 2: redraws and the two splits, two or three
 * variants each.
 *
 * Burooj on round 1 (2026-11-02): varied grounds stay; figures abstract,
 * quiet and graceful on a slow ~10 s breath, each saying something true
 * about the practice; no human silhouettes (the art elsewhere is abstract).
 *
 * Same contract as figures.js (round 4's prims), so the picks port beside
 * the Dart engine's figures:
 *   { label, says, build(r, place), draw(ctx, p, k, t, still) }
 *   place { cx, cy, s } in the unit square; inks k { paper, main, alt, line, glow }.
 * Every figure loops without a seam (sines, or phases that wrap while faded
 * out) and has a calm still frame for lists and reduced motion. No canvas
 * filters: soft edges are radial gradients, as the Dart port draws them. */
const PracticesR2 = (() => {
  'use strict';
  const C = Core, { TAU, lerp, css, mix, clamp } = C;
  const B = C.BREATH;
  const S = (t, per, ph = 0) => Math.sin(TAU * t / per + ph);
  const BR = (t, still, ph = 0) => (still ? 0.5 : 0.5 - 0.5 * Math.cos(TAU * t / B + ph)); // 0..1 on the breath
  const fade = (u) => Math.sin(Math.PI * clamp(u, 0, 1));
  const frac = (x) => x - Math.floor(x);
  const fill = (ctx, col, a = 1) => { ctx.globalAlpha = clamp(a, 0, 1); ctx.fillStyle = css(col); ctx.fill(); ctx.globalAlpha = 1; };
  // lineWidth 0 is ignored by canvas (the previous width stays), so never set it.
  const stroke = (ctx, col, w, a = 1) => { ctx.globalAlpha = clamp(a, 0, 1); ctx.strokeStyle = css(col); ctx.lineWidth = Math.max(w, 1e-4); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); ctx.globalAlpha = 1; };
  const soft = (ctx, x, y, r, col, a) => { if (r <= 0 || a <= 0) return; const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  // an elliptical soft light: a radial gradient squashed
  const softE = (ctx, x, y, rx, ry, col, a) => { if (rx <= 0 || ry <= 0 || a <= 0) return; ctx.save(); ctx.translate(x, y); ctx.scale(1, ry / rx); soft(ctx, 0, 0, rx, col, a); ctx.restore(); };
  const dot = (ctx, x, y, r) => { ctx.beginPath(); ctx.arc(x, y, Math.max(r, 0), 0, TAU); };
  const ring = dot;
  const isLight = (k) => C.lum(k.paper) > 0.3;
  // A veil of cloud or mist: lighter than the sky by day, a pale haze by night.
  const veilOf = (k) => (isLight(k) ? mix(k.paper, '#FFFFFF', 0.72) : mix(k.paper, k.main, 0.3));
  // A cloud is soft puffs, never an outline, so it cannot read as a stone.
  const PUFFS = [[0, 0, 1], [-0.42, 0.07, 0.72], [0.4, 0.08, 0.78], [0.14, -0.12, 0.8], [-0.2, -0.06, 0.7], [0.66, 0.12, 0.5], [-0.7, 0.12, 0.48]];
  function cloud(ctx, x, y, w, col, a, puffs = PUFFS) { puffs.forEach(([dx, dy, sc]) => softE(ctx, x + dx * w, y + dy * w, w * 0.55 * sc, w * 0.3 * sc, col, a)); }
  // A capsule (a soft label) centred at x, y along angle a.
  function pill(ctx, x, y, len, wid, a) { ctx.save(); ctx.translate(x, y); ctx.rotate(a); ctx.beginPath(); ctx.roundRect(-len / 2, -wid / 2, len, wid, wid / 2); ctx.restore(); }
  // a closed curve r(θ) = R(1 + Σ aₖ sin(kθ + φₖ))
  function lobed(ctx, x, y, R, waves, sy = 1, M = 120) {
    ctx.beginPath();
    for (let i = 0; i <= M; i++) { const th = TAU * i / M; let rr = 1; waves.forEach(([kk, a, ph]) => { rr += a * Math.sin(kk * th + ph); }); const px = x + R * rr * Math.cos(th), py = y + R * rr * sy * Math.sin(th); i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); }
    ctx.closePath();
  }
  const F = {};

  // ================= Insight Dialogue =================
  // Two sources take turns; neither ring set is the point. Where a ring from
  // one meets a ring from the other, a light appears: those meeting points
  // slide along still curves between them, a shape neither makes alone.
  F.dialogue_ripples = {
    label: 'two voices, one field', says: 'Insight Dialogue: each speaks and listens in turn; what arises lives where the two meet.',
    build: (r, pl) => ({ ...pl, n: 5 }),
    draw(ctx, p, k, t, still) {
      const d = p.s * 0.6, per = 1.2 * B, turn = still ? 0 : S(t, 2 * B), D = 2 * d, xL = p.cx - d, xR = p.cx + d, y = p.cy;
      const set = (off, v) => Array.from({ length: p.n }, (_, i) => { const u = still ? (i + 0.5 + off) / p.n : frac(t / per + (i + off) / p.n); return { r: p.s * (0.06 + 1.3 * u), a: fade(u) * v }; });
      const vL = 0.3 + 0.7 * (0.5 + 0.5 * turn), vR = 0.3 + 0.7 * (0.5 - 0.5 * turn);
      const L = set(0, vL), R = set(0.5, vR);
      soft(ctx, p.cx, y, p.s * 0.7, k.glow, 0.18 + 0.12 * BR(t, still));
      L.forEach((q) => { ring(ctx, xL, y, q.r); stroke(ctx, k.main, 0.005, 0.55 * q.a); });
      R.forEach((q) => { ring(ctx, xR, y, q.r); stroke(ctx, k.main, 0.005, 0.55 * q.a); });
      L.forEach((a) => R.forEach((b) => {
        const x = (D * D - b.r * b.r + a.r * a.r) / (2 * D), h2 = a.r * a.r - x * x;
        if (h2 <= 0) return;
        const h = Math.sqrt(h2), w = Math.min(1, 1.8 * a.a * b.a);
        [-1, 1].forEach((sd) => { soft(ctx, xL + x, y + sd * h, p.s * 0.12, k.glow, 0.5 * w); dot(ctx, xL + x, y + sd * h, p.s * 0.034); fill(ctx, k.alt, w); });
      }));
      [[xL, vL], [xR, vR]].forEach(([x, v]) => { soft(ctx, x, y, p.s * 0.25, k.glow, 0.5 * v); dot(ctx, x, y, p.s * 0.06); fill(ctx, k.main); });
    },
  };

  // One hand draws half a circle and stops, listening; the other answers
  // with the other half. Only when both are there does the inside light up.
  // The two halves never quite join: the form stays open.
  F.dialogue_strokes = {
    label: 'call and answer', says: 'Insight Dialogue: one speaks, pauses, the other answers; the shape is made between them.',
    build: (r, pl) => {
      const mk = (a0, a1, R, w) => { const raw = C.pen(pl.cx + R * Math.cos(a0), pl.cy + R * Math.sin(a0)).arc(pl.cx, pl.cy, R, R, a0, a1, 140).pts; return C.makeStroke(raw, { width: w, wobble: 0.006, pressure: 0.22, nib: 0.35, taper: 'brush', samples: 260 }, r); };
      return { ...pl, left: mk(-Math.PI / 2 - 0.14, -Math.PI * 1.5 + 0.16, pl.s * 0.9, 0.036), right: mk(Math.PI / 2 - 0.16, -Math.PI / 2 + 0.2, pl.s * 0.86, 0.032) };
    },
    draw(ctx, p, k, t, still) {
      const u = still ? 0.8 : frac(t / (2 * B)), out = 1 - C.ss(0.86, 1, u);
      const pl = still ? 1 : C.easeInOut(C.prog(u, 0.02, 0.3)), pr = still ? 1 : C.easeInOut(C.prog(u, 0.44, 0.28));
      const lit = (still ? 1 : C.ss(0.55, 0.78, u)) * out;
      soft(ctx, p.cx, p.cy, p.s * (0.6 + 0.25 * lit), k.glow, 0.55 * lit);
      dot(ctx, p.cx, p.cy, p.s * 0.08 * lit); fill(ctx, k.alt, lit);
      ctx.globalAlpha = out; ctx.fillStyle = css(k.main); C.drawStroke(ctx, p.left, pl);
      ctx.fillStyle = css(k.alt); C.drawStroke(ctx, p.right, pr); ctx.globalAlpha = 1;
    },
  };

  // Two lights and the thread between them: a bead of light leaves each at
  // once, and where they pass in the middle, something blooms.
  F.dialogue_thread = {
    label: 'the space between', says: 'Insight Dialogue: two people, one thread of attention; meeting, something blooms between them.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), y0 = p.cy - p.s * 0.05, x0 = p.cx - p.s * 1.05, x1 = p.cx + p.s * 1.05, sag = p.s * (0.36 - 0.14 * b);
      const at = (u) => { const v = 1 - u; return [v * v * x0 + 2 * v * u * p.cx + u * u * x1, y0 + 4 * v * u * sag]; };
      ctx.beginPath(); for (let i = 0; i <= 60; i++) { const [x, y] = at(i / 60); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } stroke(ctx, k.main, 0.008, 0.7);
      const u = still ? 0.5 : C.easeInOut(frac(t / B)), meet = Math.exp(-Math.pow((u - 0.5) / 0.1, 2));
      const [mx, my] = at(0.5);
      // the bloom: a soft light, and two rings opening from where they met
      const bloom = still ? 0.6 : frac(t / B - 0.5);
      soft(ctx, mx, my, p.s * (0.4 + 0.4 * meet), k.glow, 0.2 + 0.55 * meet);
      [0, 0.18].forEach((d) => { const v = clamp((bloom - d) / 0.5, 0, 1); if (v > 0 && v < 1) { ring(ctx, mx, my, p.s * (0.08 + 0.5 * C.easeOut(v))); stroke(ctx, k.alt, 0.007, 0.8 * fade(v)); } });
      dot(ctx, mx, my, p.s * 0.07 * (0.35 + 0.65 * meet)); fill(ctx, k.alt, 0.35 + 0.65 * meet);
      if (!still) [u, 1 - u].forEach((v) => { const [x, y] = at(v); soft(ctx, x, y, p.s * 0.14, k.glow, 0.7 * (1 - meet)); dot(ctx, x, y, p.s * 0.03); fill(ctx, k.alt, 1 - meet * 0.6); });
      [[x0, k.main], [x1, k.main]].forEach(([x, col]) => { soft(ctx, x, y0, p.s * 0.24, k.glow, 0.35); dot(ctx, x, y0, p.s * 0.075); fill(ctx, col); });
    },
  };

  // ================= Noting =================
  // Round 1's notes, bolder: each label lands in the accent, glows a moment,
  // then settles into the ink and slowly pales until its turn comes again.
  F.noting_notes = {
    label: 'light notes', says: 'Noting: a soft label for each thing as it comes — rising, falling, hearing.',
    build: (r, pl) => ({ ...pl, rows: [0, 1, 2].map(() => Array.from({ length: 6 }, () => ({ w: r.range(0.14, 0.32), gap: r.range(0.08, 0.12) }))) }),
    draw(ctx, p, k, t, still) {
      const per = 1.8, n = 18, now = still ? 10.95 : (t / per) % n;
      let idx = 0;
      p.rows.forEach((row, ri) => {
        let x = p.cx - p.s * 1.1; const y = p.cy + (ri - 1) * p.s * 0.5;
        row.forEach((m) => {
          const age = (now - idx + n) % n, w = m.w * p.s, fits = x + w <= p.cx + p.s * 1.12;
          if (fits) {
            const grow = age < 1 ? C.easeOut(age * 1.6) : 1, a = age < 1 ? 1 : Math.max(0.32, 1 - (age - 1) / 12);
            if (age < 1.5) soft(ctx, x + w / 2, y, p.s * 0.3, k.glow, 0.45 * fade(age / 1.5));
            pill(ctx, x + (w * grow) / 2, y, Math.max(w * grow, 0.001), p.s * 0.11, 0); fill(ctx, age < 1.2 ? k.alt : k.main, a);
          }
          x += w + m.gap * p.s; idx++;
        });
      });
    },
  };

  // Things drift through: a sound, a thought, a touch. Each one, crossing
  // the place of knowing, is touched by a light note and let go.
  F.noting_touch = {
    label: 'touched and let go', says: 'Noting: each thing that comes is touched by a light label as it passes, and let go.',
    build: (r, pl) => ({ ...pl, items: Array.from({ length: 6 }, (_, i) => ({ kind: ['dot', 'wave', 'ring', 'pair', 'dash', 'wave'][i], y: [-0.5, 0.12, -0.15, 0.45, -0.35, 0.28][i] + r.range(-0.05, 0.05), ph: i / 6 + r.range(-0.03, 0.03) })) }),
    draw(ctx, p, k, t, still) {
      const per = 2.6 * B, sz = p.s * 0.14;
      ctx.beginPath(); ctx.moveTo(p.cx, p.cy - p.s * 0.85); ctx.lineTo(p.cx, p.cy + p.s * 0.85); stroke(ctx, k.line, 0.005, 0.35);
      p.items.forEach((q) => {
        const u = still ? frac(q.ph + 0.5 - p.items[1].ph) : frac(t / per + q.ph), x = p.cx + p.s * lerp(1.45, -1.45, u), y = p.cy + q.y * p.s + p.s * 0.04 * Math.sin(u * TAU * 2 + q.ph * 9);
        const life = Math.pow(fade(u), 0.6), noted = Math.exp(-Math.pow((u - 0.5) / 0.035, 2)), after = u > 0.5 ? 0.55 + 0.45 * (1 - (u - 0.5) * 2) : 1, a = life * after;
        ctx.beginPath();
        if (q.kind === 'dot') { dot(ctx, x, y, sz * 0.7); fill(ctx, k.main, a); }
        else if (q.kind === 'ring') { ring(ctx, x, y, sz * 0.75); stroke(ctx, k.main, 0.01, a); }
        else if (q.kind === 'pair') { dot(ctx, x - sz * 0.6, y, sz * 0.45); fill(ctx, k.main, a); dot(ctx, x + sz * 0.6, y, sz * 0.45); fill(ctx, k.main, a); }
        else if (q.kind === 'dash') { pill(ctx, x, y, sz * 2.2, sz * 0.55, 0); fill(ctx, k.main, a); }
        else { for (let i = 0; i <= 24; i++) { const v = i / 24, xx = x + (v - 0.5) * sz * 3, yy = y + Math.sin(v * TAU * 1.5) * sz * 0.5; i ? ctx.lineTo(xx, yy) : ctx.moveTo(xx, yy); } stroke(ctx, k.main, 0.011, a); }
        if (noted > 0.01) { soft(ctx, x, y, p.s * 0.28, k.glow, 0.55 * noted); pill(ctx, x, y - sz * 1.6, sz * 1.9 * (0.6 + 0.4 * noted), sz * 0.5, 0); fill(ctx, k.alt, noted); }
      });
    },
  };

  // The breath as a line moving past: as each rise and each fall passes
  // the moment of now, it gets its note, pinned to the slope, then fades.
  F.noting_rise = {
    label: 'rising, falling', says: 'Noting: “rising… falling…” — each movement of the breath named as it passes.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const lam = p.s * 1.5, kk = TAU / lam, A = p.s * 0.36, ph = still ? 0.6 : TAU * t / B, x0 = p.cx - p.s * 1.25, x1 = p.cx + p.s * 1.25;
      const Y = (x) => p.cy + A * Math.sin(kk * (x - p.cx) + ph);
      ctx.beginPath(); ctx.moveTo(p.cx, p.cy - p.s * 0.75); ctx.lineTo(p.cx, p.cy + p.s * 0.75); stroke(ctx, k.line, 0.005, 0.3);
      for (let x = x0; x < x1; x += 0.004) { ctx.beginPath(); ctx.moveTo(x, Y(x)); ctx.lineTo(x + 0.0045, Y(x + 0.0045)); stroke(ctx, k.main, 0.012, 0.95 * Math.min(1, (x - x0) / (p.s * 0.5), (x1 - x) / (p.s * 0.5))); }
      // slope midpoints sit where the phase is a multiple of π
      const j0 = Math.ceil((kk * (x0 - p.cx) + ph) / Math.PI), j1 = Math.floor((kk * (p.cx - p.cx) + ph) / Math.PI);
      for (let j = j0; j <= j1; j++) {
        const x = p.cx + (j * Math.PI - ph) / kk, y = Y(x), passed = p.cx - x, born = C.easeOut(clamp(passed / (p.s * 0.1), 0, 1)), a = born * Math.min(1, 1 - (passed - p.s * 0.1) / (p.s * 1.2));
        const slope = A * kk * Math.cos(j * Math.PI), ang = Math.atan(slope), rising = slope < 0;
        if (a <= 0) continue;
        if (passed < p.s * 0.4) soft(ctx, x + Math.sin(ang) * p.s * 0.2 * (rising ? 1 : -1), y - Math.cos(ang) * p.s * 0.2 * (rising ? 1 : -1), p.s * 0.3, k.glow, 0.5 * (1 - passed / (p.s * 0.4)));
        const off = p.s * 0.2, nx = Math.sin(ang), ny = -Math.cos(ang), side = rising ? 1 : -1;
        pill(ctx, x + nx * off * side, y + ny * off * side, p.s * 0.32 * born, p.s * 0.12, ang); fill(ctx, rising ? k.alt : k.main, a);
      }
    },
  };

  // ================= Effortless mindfulness =================
  // Soft veils part to show the clear light that was behind them all along.
  F.glimpse_part = {
    label: 'a parting cloud', says: 'Effortless mindfulness: the clouds part for a moment, and the clear light was there all along.',
    build: (r, pl) => ({ ...pl, cl: [[-1, -0.32, 0.95], [-1, 0.3, 0.8], [1, -0.22, 0.85], [1, 0.36, 0.95]].map(([sd, y, w]) => ({ sd, y, w, ph: r.range(0, TAU) })) }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.5 : frac(t / (2 * B)), open = Math.pow(fade(u), 1.4), veil = veilOf(k);
      soft(ctx, p.cx, p.cy, p.s * (0.55 + 0.6 * open), k.glow, 0.25 + 0.5 * open);
      dot(ctx, p.cx, p.cy, p.s * 0.09 * (0.4 + 0.6 * open)); fill(ctx, k.alt, 0.4 + 0.6 * open);
      p.cl.forEach((c) => {
        const x = p.cx + c.sd * p.s * (0.3 + 0.62 * open) + (still ? 0 : p.s * 0.03 * S(t, 17, c.ph));
        cloud(ctx, x, p.cy + c.y * p.s, p.s * c.w, veil, 0.78);
      });
    },
  };

  // Attention narrowed to a tight bright ring lets go: it widens and
  // dissolves into the soft light that was already everywhere.
  F.glimpse_widen = {
    label: 'dropping back', says: 'Effortless mindfulness: narrow attention lets go and opens into the awareness already here.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.52 : frac(t / (2 * B)), w = C.ss(0.36, 0.86, u), open = w * (1 - C.ss(0.86, 1, u));
      soft(ctx, p.cx, p.cy, p.s * (0.9 + 0.7 * open), k.glow, 0.16 + 0.42 * open);
      const jit = (1 - w) * p.s * 0.012 * (still ? 0 : S(t, 1.3)), rr = p.s * lerp(0.2, 1.7, C.easeOut(w)) + jit;
      const a = (1 - w) * (still ? 1 : C.ss(0, 0.1, u));
      ring(ctx, p.cx, p.cy, rr); stroke(ctx, k.main, 0.004 + 0.012 * (1 - w), a);
      if (w > 0 && w < 1) { ring(ctx, p.cx, p.cy, rr * 0.86); stroke(ctx, k.glow, 0.02 * w, 0.5 * fade(w)); }
      dot(ctx, p.cx, p.cy, p.s * 0.055); fill(ctx, k.alt);
    },
  };

  // A steady light, and soft veils drifting past in front of it. The veils
  // thin on the out-breath; the light never moves.
  F.glimpse_veils = {
    label: 'already here', says: 'Effortless mindfulness: veils drift past a light that never moved.',
    build: (r, pl) => ({ ...pl, veils: Array.from({ length: 5 }, (_, i) => ({ y: [-0.46, -0.12, 0.2, 0.5, -0.3][i] + r.range(-0.05, 0.05), w: r.range(0.55, 0.85), ph: i / 5 + r.range(-0.04, 0.04), per: r.range(34, 46) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), veil = veilOf(k), ly = p.cy - p.s * 0.05;
      soft(ctx, p.cx, ly, p.s * 0.95, k.glow, 0.5);
      dot(ctx, p.cx, ly, p.s * 0.2); fill(ctx, k.alt);
      p.veils.forEach((v) => {
        const u = still ? frac(v.ph + 0.15) : frac(t / v.per + v.ph), x = p.cx + p.s * lerp(-2.0, 2.0, u);
        cloud(ctx, x, p.cy + v.y * p.s, p.s * v.w, veil, (0.6 + 0.3 * (1 - b)) * fade(u), PUFFS.slice(0, 5).map(([dx, dy, sc]) => [dx * 1.4, dy * 0.5, sc]));
      });
    },
  };

  // ================= Kāyagatāsati =================
  // A field of points, not a body: a soft band of attention sweeps down and
  // back up, and each point it passes wakes, then settles.
  F.body_sweep = {
    label: 'a slow sweep', says: 'Kāyagatāsati: attention sweeping through the body, waking each part as it passes.',
    build: (r, pl) => {
      const pts = [], sp = 0.15;
      for (let row = -8; row <= 8; row++) for (let col = -8; col <= 8; col++) {
        const x = (col + (row % 2 ? 0.5 : 0)) * sp + r.range(-0.03, 0.03), y = row * sp * 0.87 + r.range(-0.03, 0.03), d = Math.hypot(x / 0.92, y / 1.08);
        if (d < 1) pts.push({ x, y, d, z: r.range(0.75, 1.25) });
      }
      return { ...pl, pts };
    },
    draw(ctx, p, k, t, still) {
      const u = still ? 0.38 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), band = lerp(-1.15, 1.15, u);
      softE(ctx, p.cx, p.cy + band * p.s, p.s * 1.2, p.s * 0.3, k.glow, 0.35);
      p.pts.forEach((q) => {
        const wake = Math.exp(-Math.pow((q.y - band) / 0.16, 2)), edge = 1 - C.ss(0.82, 1, q.d);
        dot(ctx, p.cx + q.x * p.s, p.cy + q.y * p.s, p.s * 0.026 * q.z * (1 + 1.1 * wake));
        fill(ctx, wake > 0.45 ? k.alt : k.main, (0.38 + 0.62 * wake) * edge);
      });
    },
  };

  // A resting pebble breathing between perfect and imperfect; the band of
  // attention passes through it and, inside the band, sensation shows.
  F.body_pebble = {
    label: 'through the stone', says: 'Kāyagatāsati: attention passing slowly through the body, and sensation showing where it rests.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy + pl.s * 0.05, pl.s * 0.72, 0.9, 0.002), grain: Array.from({ length: 150 }, () => ({ x: r.range(-0.8, 0.8), y: r.range(-1.1, 1.1), z: r.range(0.008, 0.02), ph: r.range(0, TAU) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), u = still ? 0.4 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), band = p.cy + p.s * lerp(-1.05, 1.15, u), o = { imperf: 1 - 0.5 * b, grow: 0.97 + 0.03 * b, sx: 0.78, sy: 1.22 };
      C.blobPath(ctx, p.blob, o); fill(ctx, k.main, 0.2);
      ctx.save(); C.blobPath(ctx, p.blob, o); ctx.clip();
      softE(ctx, p.cx, band, p.s * 1.1, p.s * 0.26, k.glow, 0.75);
      p.grain.forEach((g) => { const y = p.cy + g.y * p.s, w = Math.exp(-Math.pow((y - band) / (p.s * 0.2), 2)); if (w < 0.03) return; dot(ctx, p.cx + g.x * p.s, y, g.z * (still ? 1 : 0.8 + 0.4 * (0.5 + 0.5 * S(t, 2.3, g.ph)))); fill(ctx, k.alt, w); });
      ctx.restore();
      C.blobPath(ctx, p.blob, o); stroke(ctx, k.main, 0.007, 0.75);
    },
  };

  // The body as terrain: contour lines, and attention moving from the
  // outermost inward and back, one layer at a time — skin, flesh, bone.
  F.body_contours = {
    label: 'layer by layer', says: 'Kāyagatāsati: the body contemplated layer by layer, from the skin inward and back.',
    build: (r, pl) => {
      const waves = [[2, r.range(0.06, 0.1), r.range(0, TAU)], [3, r.range(0.03, 0.06), r.range(0, TAU)], [5, r.range(0.01, 0.025), r.range(0, TAU)]];
      return { ...pl, n: 7, waves, ox: r.range(-0.15, 0.15), oy: r.range(-0.2, 0.05) };
    },
    draw(ctx, p, k, t, still) {
      const at = still ? 2.3 : (p.n - 1) * (0.5 - 0.5 * Math.cos(TAU * t / (3 * B))), b = BR(t, still);
      for (let i = 0; i < p.n; i++) {
        const f = i / (p.n - 1), x = p.cx + p.ox * p.s * f, y = p.cy + p.oy * p.s * f, R = p.s * lerp(1.12, 0.16, f) * (0.98 + 0.02 * b);
        const lit = Math.max(0, 1 - Math.abs(at - i) * 1.1), wv = p.waves.map(([kk, a, ph]) => [kk, a * (1 - 0.5 * f), ph + f * 0.6]);
        lobed(ctx, x, y, R, wv, 1.08);
        if (lit > 0) fill(ctx, k.glow, 0.22 * lit);
        stroke(ctx, lit > 0.4 ? k.alt : k.main, 0.006 + 0.008 * lit, 0.45 + 0.55 * lit);
      }
      dot(ctx, p.cx + p.ox * p.s, p.cy + p.oy * p.s, p.s * 0.05); fill(ctx, k.alt);
    },
  };

  return F;
})();
