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
            pill(ctx, x + (w * grow) / 2, y, Math.max(w * grow, 0.001), p.s * 0.11, 0); fill(ctx, mix(k.alt, k.main, C.ss(0.8, 2.2, age)), a);
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
        fill(ctx, mix(k.main, k.alt, C.ss(0.25, 0.7, wake)), (0.38 + 0.62 * wake) * edge);
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
        stroke(ctx, mix(k.main, k.alt, C.ss(0.2, 0.7, lit)), 0.006 + 0.008 * lit, 0.45 + 0.55 * lit);
      }
      dot(ctx, p.cx + p.ox * p.s, p.cy + p.oy * p.s, p.s * 0.05); fill(ctx, k.alt);
    },
  };

  // ================= Prāṇa · Qì =================
  // Field lines of one breathing field: light rises through the centre,
  // spills over and returns from below, every line meeting at one point.
  F.energy_field = {
    label: 'the field', says: 'Prāṇa and qì: energy circling through one field that opens and closes with the breath.',
    build: (r, pl) => ({ ...pl, L: [0.42, 0.68, 0.94, 1.2], motes: Array.from({ length: 32 }, (_, i) => ({ li: i % 4, sd: (i >> 2) % 2 ? 1 : -1, ph: r.next(), sp: r.range(0.85, 1.15) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), sc = p.s * (0.9 + 0.1 * b), sy = 1.75;
      const at = (L, th, sd) => { const r2 = L * Math.sin(th) ** 2; return [p.cx + sd * sc * r2 * Math.sin(th), p.cy - sc * sy * r2 * Math.cos(th)]; };
      soft(ctx, p.cx, p.cy, p.s * (0.8 + 0.3 * b), k.glow, 0.28);
      p.L.forEach((L, li) => [-1, 1].forEach((sd) => {
        ctx.beginPath(); for (let i = 0; i <= 80; i++) { const [x, y] = at(L, 0.02 + (Math.PI - 0.04) * i / 80, sd); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
        stroke(ctx, k.main, 0.005, 0.22 + 0.1 * li);
      }));
      p.motes.forEach((m) => {
        const v = still ? m.ph : frac(t / (2 * B) * m.sp + m.ph), [x, y] = at(p.L[m.li], Math.PI * v, m.sd), a = fade(v);
        dot(ctx, x, y, p.s * 0.03 * (0.6 + 0.4 * a)); fill(ctx, m.li % 2 ? k.alt : k.glow, 0.95 * a);
      });
      soft(ctx, p.cx, p.cy, p.s * 0.3, k.glow, 0.6 + 0.3 * b); dot(ctx, p.cx, p.cy, p.s * 0.06); fill(ctx, k.alt);
    },
  };

  // No outline at all: a cloud of fine motes that widens on the in-breath,
  // gathers on the out-breath, each mote shimmering on its own clock.
  F.energy_motes = {
    label: 'a shimmering field', says: 'Prāṇa and qì: the body felt as a shimmering field that widens with the in-breath.',
    build: (r, pl) => ({ ...pl, m: Array.from({ length: 120 }, (_, i) => { const d = Math.min(1.1, Math.sqrt(-2 * Math.log(1 - r.next() * 0.96)) * 0.42); return { a: r.range(0, TAU), d, ph: r.range(0, TAU), per: r.range(3, 7), z: r.range(0.012, 0.03), hot: i % 7 === 0 }; }) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * (0.82 + 0.28 * b);
      soft(ctx, p.cx, p.cy, R * 1.25, k.glow, 0.22 + 0.12 * b);
      p.m.forEach((m) => {
        const a = m.a + (still ? 0 : t * 0.03 * (1.2 - m.d)), tw = still ? 0.7 : 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(TAU * t / m.per + m.ph));
        dot(ctx, p.cx + Math.cos(a) * m.d * R, p.cy + Math.sin(a) * m.d * R * 1.12, p.s * m.z); fill(ctx, m.hot ? k.alt : k.glow, tw * (1 - 0.4 * C.ss(0.7, 1.1, m.d)));
      });
    },
  };

  // The small circuit: a light rises up the back on the in-breath, pauses
  // at the crown, comes down the front on the out-breath and rests below.
  F.energy_orbit = {
    label: 'the small circuit', says: 'Qì: a light circling up the back on the in-breath and down the front on the out-breath.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const rx = p.s * 0.62, ry = p.s * 0.98, y0 = p.cy;
      const phiAt = (tt) => { const h = 2 * tt / B; return Math.PI / 2 + Math.PI * (Math.floor(h) + C.easeInOut(frac(h))); };
      const P = (phi) => [p.cx + rx * Math.cos(phi), y0 + ry * Math.sin(phi)];
      ctx.beginPath(); ctx.ellipse(p.cx, y0, rx, ry, 0, 0, TAU); stroke(ctx, k.main, 0.006, 0.4);
      soft(ctx, p.cx, y0 + ry * 0.62, p.s * 0.42, k.glow, 0.5); dot(ctx, p.cx, y0 + ry * 0.62, p.s * 0.07); fill(ctx, k.alt, 0.85);
      dot(ctx, p.cx, y0 - ry, p.s * 0.03); fill(ctx, k.main, 0.6);
      const tt = still ? 3.4 : t;
      for (let i = 24; i >= 0; i--) { const [x, y] = P(phiAt(tt - i * 0.07)); dot(ctx, x, y, p.s * (0.055 - 0.0016 * i)); fill(ctx, i ? k.glow : k.alt, i ? 0.55 * (1 - i / 25) : 1); }
      const [hx, hy] = P(phiAt(tt)); soft(ctx, hx, hy, p.s * 0.28, k.glow, 0.6);
    },
  };

  // ================= Focusing =================
  // Something vague and grey, listened to, comes slowly into focus and
  // warms; at its clearest it shifts — a release goes out — and blurs again.
  F.focus_blur = {
    label: 'coming into focus', says: 'Focusing: a vague felt something, listened to, comes clear, and shifts.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.6, 2.6, 0.002) }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.3 : frac(t / (2 * B)), c = 0.5 - 0.5 * Math.cos(TAU * u), col = mix(k.main, k.alt, c);
      soft(ctx, p.cx, p.cy, p.s * (1.1 - 0.3 * c), k.glow, 0.25 + 0.25 * c);
      for (let i = 6; i >= 0; i--) { C.blobPath(ctx, p.blob, { grow: 1 + (1 - c) * 0.09 * i, imperf: 1 - 0.3 * c }); fill(ctx, col, 0.08 + 0.06 * c); }
      C.blobPath(ctx, p.blob, { imperf: 1 - 0.3 * c }); fill(ctx, col, 0.75 * c * c);
      const v = clamp((u - 0.5) / 0.3, 0, 1);
      if (v > 0 && v < 1) { C.blobPath(ctx, p.blob, { grow: 1 + 1.1 * C.easeOut(v), imperf: 1 - 0.3 * c }); stroke(ctx, k.alt, 0.007, 0.8 * fade(v)); }
    },
  };

  // A felt sense, and a word for it held up beside it: too big, too small,
  // closer, until it fits — and both glow, and the felt sense eases.
  F.focus_handle = {
    label: 'a handle that fits', says: 'Focusing: trying words against the felt sense until one fits, and it eases.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.5, 2.8, 0.002) }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.7 : frac(t / (3 * B)), fit = C.ss(0.5, 0.62, u) * (1 - C.ss(0.88, 1, u)), seek = 1 - C.ss(0.05, 0.6, u);
      const ease = still ? 1 : C.ss(0.6, 0.8, u) * (1 - C.ss(0.9, 1, u));
      const o = { imperf: 1 - 0.55 * ease, grow: 1 + 0.08 * ease };
      soft(ctx, p.cx, p.cy, p.s * (0.8 + 0.4 * fit), k.glow, 0.2 + 0.45 * fit);
      C.blobPath(ctx, p.blob, o); fill(ctx, mix(k.main, k.alt, 0.2 + 0.5 * ease), 0.5 + 0.35 * ease);
      const R = p.s * 0.62 * (1 + 0.5 * seek * Math.sin(u * TAU * 2.6)), a = (still ? 1 : C.ss(0, 0.08, u)) * (1 - C.ss(0.86, 0.98, u));
      ring(ctx, p.cx, p.cy, R); stroke(ctx, mix(k.main, k.alt, fit), 0.008 + 0.006 * fit, a);
    },
  };

  // A fern's crozier: tightly curled, it unrolls a little with each breath
  // and a long way at the shift, then gathers again. Carrying forward.
  F.focus_unfurl = {
    label: 'unfurling', says: 'Focusing: the felt shift, something curled up in the body loosening and unfolding.',
    build: (r, pl) => ({ ...pl, lean: r.range(-0.1, 0.05) }),
    draw(ctx, p, k, t, still) {
      const open = still ? 0.35 : C.easeInOut(0.5 - 0.5 * Math.cos(TAU * t / (3 * B))) * 0.8 + 0.2 * BR(t, still);
      const N = 150, Lw = p.s * 2.6, ds = Lw / N, turn = lerp(3.4, 1.1, open) * Math.PI;
      let x = p.cx - p.s * 0.3, y = p.cy + p.s * 1.15, h = -Math.PI / 2 + p.lean;
      const pts = [[x, y]];
      for (let i = 1; i <= N; i++) { const v = i / N; h += turn * 3.4 * Math.pow(v, 2.4) / N; x += Math.cos(h) * ds; y += Math.sin(h) * ds; pts.push([x, y]); }
      const tip = pts[N];
      soft(ctx, tip[0], tip[1], p.s * (0.35 + 0.3 * open), k.glow, 0.3 + 0.35 * open);
      for (let i = 0; i < N; i++) { ctx.beginPath(); ctx.moveTo(pts[i][0], pts[i][1]); ctx.lineTo(pts[i + 1][0], pts[i + 1][1]); stroke(ctx, k.main, p.s * lerp(0.16, 0.035, Math.pow(i / N, 0.8))); }
      dot(ctx, tip[0], tip[1], p.s * 0.05); fill(ctx, k.alt);
    },
  };

  // ================= Yoga nidrā =================
  // Five sheaths, outermost first, settle from restless waves to stillness,
  // one after another; above them, one point of awareness stays lit.
  F.nidra_sheaths = {
    label: 'five sheaths settling', says: 'Yoga nidrā: layer after layer settles into rest, and awareness stays awake.',
    build: (r, pl) => ({ ...pl, ph: Array.from({ length: 5 }, () => r.range(0, TAU)) }),
    draw(ctx, p, k, t, still) {
      const depth = still ? 0.55 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), b = BR(t, still), ay = p.cy - p.s * 0.92;
      for (let i = 0; i < 5; i++) {
        const settle = C.ss(i * 0.12, i * 0.12 + 0.45, depth), y = p.cy + p.s * (0.92 - i * 0.34 + 0.05 * settle), A = p.s * (0.13 * (1 - settle) + 0.008);
        ctx.beginPath();
        for (let j = 0; j <= 60; j++) { const v = j / 60, x = p.cx + p.s * lerp(-1.15, 1.15, v); const yy = y + A * Math.sin(TAU * v * (1.6 + 0.3 * i) + p.ph[i] + (still ? 0 : t * 0.35)) * fade(v); j ? ctx.lineTo(x, yy) : ctx.moveTo(x, yy); }
        stroke(ctx, k.main, 0.008, 0.35 + 0.45 * (1 - i / 5));
      }
      soft(ctx, p.cx, ay, p.s * (0.3 + 0.25 * depth + 0.05 * b), k.glow, 0.5 + 0.3 * depth);
      dot(ctx, p.cx, ay, p.s * 0.06); fill(ctx, k.alt);
    },
  };

  // One line from waking to sleep: quick small waves slow into long deep
  // ones. A point of awareness rides it all the way and stays bright.
  F.nidra_waves = {
    label: 'into the slow waves', says: 'Yoga nidrā: the mind’s waves slowing towards sleep, with awareness riding them.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const N = 220, x0 = p.cx - p.s * 1.25, x1 = p.cx + p.s * 1.25, scroll = still ? 0 : TAU * t / B;
      const pts = []; let ph = 0;
      for (let i = 0; i <= N; i++) { const v = i / N; ph += TAU * lerp(9, 1.1, Math.pow(v, 0.6)) / N; pts.push([lerp(x0, x1, v), p.cy + p.s * lerp(0.05, 0.42, v) * Math.sin(ph - scroll)]); }
      for (let i = 0; i < N; i++) { const v = i / N; ctx.beginPath(); ctx.moveTo(pts[i][0], pts[i][1]); ctx.lineTo(pts[i + 1][0], pts[i + 1][1]); stroke(ctx, k.main, 0.009, 0.9 * Math.min(1, v * 6, (1 - v) * 6)); }
      const u = still ? 0.62 : frac(t / (2 * B)), j = Math.round(C.easeInOut(u) * N), [x, y] = pts[j], a = fade(u);
      soft(ctx, x, y, p.s * 0.35, k.glow, 0.65 * a); dot(ctx, x, y, p.s * 0.055); fill(ctx, k.alt, a);
    },
  };

  // A level line, lying down; the moon sinks towards it and rises again;
  // on the line one small light keeps watch the whole night.
  F.nidra_moon = {
    label: 'the edge of sleep', says: 'Yoga nidrā: lying level at the edge of sleep, with one light that stays awake.',
    build: (r, pl) => ({ ...pl, bars: Array.from({ length: 4 }, () => r.range(0, TAU)) }),
    draw(ctx, p, k, t, still) {
      const hy = p.cy + p.s * 0.38, sink = still ? 0.45 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), mx = p.cx + p.s * 0.45, my = lerp(p.cy - p.s * 0.75, hy - p.s * 0.28, sink), R = p.s * 0.2;
      ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 1, hy); ctx.clip();
      soft(ctx, mx, my, p.s * 0.6, k.glow, 0.35);
      ctx.beginPath(); ctx.arc(mx, my, R, 0, TAU); ctx.arc(mx + R * 0.42, my - R * 0.22, R * 0.86, 0, TAU, true); fill(ctx, k.alt);
      ctx.restore();
      p.bars.forEach((ph, i) => { const y = hy + p.s * (0.1 + i * 0.1), w = p.s * (0.36 - i * 0.06) * (1 + (still ? 0 : 0.2 * S(t, 6 + i, ph))); pill(ctx, mx, y, w, p.s * 0.035, 0); fill(ctx, k.alt, (0.5 - i * 0.1) * (1 - 0.5 * sink)); });
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.25, hy); ctx.lineTo(p.cx + p.s * 1.25, hy); stroke(ctx, k.main, 0.008, 0.75);
      const lx = p.cx - p.s * 0.55;
      soft(ctx, lx, hy, p.s * (0.3 + 0.05 * BR(t, still)), k.glow, 0.7); dot(ctx, lx, hy - p.s * 0.02, p.s * 0.05); fill(ctx, k.glow);
    },
  };

  // ================= Headless Way =================
  // Face to no-face: over there, a face, solid; here, no face — open space
  // with that face, and the world, in it.
  F.headless_face = {
    label: 'face to no-face', says: 'The Headless Way: there, a face; here, no face — open space, with the world in it.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.46, lx = p.cx - p.s * 0.56, rx = p.cx + p.s * 0.6, y = p.cy;
      dot(ctx, rx, y, R); fill(ctx, k.main);
      soft(ctx, lx, y, R * (1.5 + 0.15 * b), k.glow, 0.45 + 0.1 * b);
      ctx.save(); dot(ctx, lx, y, R * 1.06); ctx.clip();
      soft(ctx, lx, y, R * 1.15, mix(k.paper, '#FFFFFF', isLight(k) ? 0.6 : 0.1), 0.95);
      ctx.beginPath(); ctx.moveTo(lx - R * 1.2, y + R * 0.42); ctx.quadraticCurveTo(lx, y + R * 0.3, lx + R * 1.2, y + R * 0.46); ctx.lineTo(lx + R * 1.2, y + R * 1.2); ctx.lineTo(lx - R * 1.2, y + R * 1.2); ctx.closePath(); fill(ctx, k.line, 0.22);
      dot(ctx, lx - R * 0.45, y - R * 0.38, R * 0.14); fill(ctx, k.alt);
      dot(ctx, lx + R * 0.22, y - R * 0.02, R * (0.36 + 0.03 * b)); fill(ctx, k.main, 0.9);
      ctx.restore();
      ctx.setLineDash([0.006, 0.012]); ring(ctx, lx, y, R * 1.06); stroke(ctx, k.main, 0.004, 0.45); ctx.setLineDash([]);
    },
  };

  // The single eye: the world, vivid inside a wide open space with no
  // edge, fading to nothing all round. The space breathes.
  F.headless_eye = {
    label: 'the single eye', says: 'The Headless Way: looking out from no head — one wide open space, full of the world.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), rx = p.s * (1.6 + 0.12 * b), ry = p.s * 1.05 * (1 + 0.05 * b);
      dot(ctx, p.cx + p.s * 0.35, p.cy - p.s * 0.2, p.s * 0.1); fill(ctx, k.alt);
      soft(ctx, p.cx + p.s * 0.35, p.cy - p.s * 0.2, p.s * 0.4, k.glow, 0.45);
      ctx.save(); ctx.translate(p.cx, p.cy); ctx.scale(1, ry / rx);
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, rx); g.addColorStop(0, css(k.paper, 0)); g.addColorStop(0.62, css(k.paper, 0)); g.addColorStop(0.95, css(k.paper, 0.92)); g.addColorStop(1, css(k.paper, 1));
      ctx.fillStyle = g; ctx.fillRect(-2, -4, 4, 8); ctx.restore();
    },
  };

  // Pointing at things: each is solid, a thing. Then pointing back here,
  // where the head should be — and finding open space, full of the things.
  F.headless_point = {
    label: 'pointing back', says: 'The Headless Way: point at things, each a thing; point back here, and find open space.',
    build: (r, pl) => ({ ...pl, things: [[-0.95, 0.42, 0.11], [-0.62, -0.32, 0.09], [0.92, 0.18, 0.12]] }),
    draw(ctx, p, k, t, still) {
      const px = p.cx, py = p.cy + p.s * 0.72, top = [p.cx, p.cy - p.s * 0.62], R = p.s * 0.34;
      const targets = [...p.things.map(([x, y]) => [p.cx + x * p.s, p.cy + y * p.s]), top], ang = targets.map(([x, y]) => Math.atan2(y - py, x - px));
      const h = still ? 3 : frac(t / (3 * B)) * 4, i = Math.floor(h), f = C.ss(0.6, 1, h - i), a = lerp(ang[i], ang[(i + 1) % 4], f), on = (j) => (j === i ? 1 - f : j === (i + 1) % 4 ? f : 0);
      const back = on(3);
      soft(ctx, top[0], top[1], R * (1.4 + 0.5 * back), k.glow, 0.15 + 0.5 * back);
      ring(ctx, top[0], top[1], R); stroke(ctx, k.main, 0.006, 0.35 + 0.4 * back);
      p.things.forEach(([x, y, z], j) => {
        const tx = p.cx + x * p.s, ty = p.cy + y * p.s;
        if (on(j) > 0.01) soft(ctx, tx, ty, p.s * 0.3, k.glow, 0.45 * on(j));
        dot(ctx, tx, ty, p.s * z); fill(ctx, k.main);
        dot(ctx, top[0] + x * R * 0.42, top[1] + y * R * 0.42, p.s * z * 0.35); fill(ctx, k.main, 0.75 * back);
      });
      const L = p.s * 0.55, ex = px + Math.cos(a) * L, ey = py + Math.sin(a) * L;
      ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(ex, ey); stroke(ctx, k.alt, 0.012);
      ctx.beginPath(); ctx.moveTo(ex + Math.cos(a) * p.s * 0.09, ey + Math.sin(a) * p.s * 0.09); ctx.lineTo(ex + Math.cos(a + 2.4) * p.s * 0.07, ey + Math.sin(a + 2.4) * p.s * 0.07); ctx.lineTo(ex + Math.cos(a - 2.4) * p.s * 0.07, ey + Math.sin(a - 2.4) * p.s * 0.07); ctx.closePath(); fill(ctx, k.alt);
      dot(ctx, px, py, p.s * 0.05); fill(ctx, k.alt);
    },
  };

  // ================= Dzogchen and Mahāmudrā =================
  // Kin, not the same: both are drawn round one clear disc, the mind's
  // nature. Dzogchen rests as the disc (open, clear, lit from itself);
  // Mahāmudrā watches what arises in it and knows it as the disc.
  function clearDisc(ctx, x, y, R, k, b) {
    const g = ctx.createRadialGradient(x - R * 0.25, y - R * 0.3, 0, x, y, R);
    g.addColorStop(0, css(mix(k.paper, k.glow, 0.32), 0.95)); g.addColorStop(0.7, css(mix(k.paper, k.main, 0.1), 0.85)); g.addColorStop(1, css(mix(k.paper, k.main, 0.18), 0.85));
    ctx.fillStyle = g; dot(ctx, x, y, R); ctx.fill();
    ring(ctx, x, y, R); stroke(ctx, k.main, 0.006, 0.5);
    ctx.beginPath(); ctx.arc(x, y, R * 0.86, Math.PI * 1.08, Math.PI * (1.08 + 0.3 + 0.08 * b)); stroke(ctx, mix(k.glow, '#FFFFFF', 0.5), 0.008, 0.5);
  }
  const FIVE = (k) => [mix(k.glow, '#FFFFFF', 0.45), k.glow, k.alt, mix(k.alt, k.main, 0.45), mix(k.main, k.paper, 0.3)];

  // The mirror: lights pass before it and show in it, vivid while they
  // are there; the mirror takes nothing and keeps nothing.
  F.dzogchen_mirror = {
    label: 'the mirror', says: 'Dzogchen: like a mirror, the mind shows everything and is stained by nothing.',
    build: (r, pl) => ({ ...pl, lights: Array.from({ length: 5 }, (_, i) => ({ y: r.range(-0.6, 0.6), ph: i / 5 + r.range(-0.03, 0.03), z: r.range(0.08, 0.14), ci: i })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.85, five = FIVE(k);
      soft(ctx, p.cx, p.cy, R * 1.5, k.glow, 0.2 + 0.08 * b);
      clearDisc(ctx, p.cx, p.cy, R, k, b);
      ctx.save(); dot(ctx, p.cx, p.cy, R * 0.98); ctx.clip();
      p.lights.forEach((l) => { const u = still ? frac(l.ph + 0.1) : frac(t / (4 * B) + l.ph), x = p.cx + p.s * lerp(-1.3, 1.3, u), y = p.cy + l.y * p.s; soft(ctx, x, y, p.s * l.z * 2.6, five[l.ci], 0.75 * fade(u)); dot(ctx, x, y, p.s * l.z * 0.6); fill(ctx, five[l.ci], 0.9 * fade(u)); });
      ctx.restore();
    },
  };

  // The thigle: a sphere of five lights, open at the centre, its light
  // welling outward from nowhere, ring after ring, on the breath.
  F.dzogchen_thigle = {
    label: 'a sphere of five lights', says: 'Dzogchen: the mind’s nature, open at the centre, its light arising by itself.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), five = FIVE(k);
      soft(ctx, p.cx, p.cy, p.s * 1.3, k.glow, 0.25 + 0.1 * b);
      for (let i = 0; i < 5; i++) {
        const w = still ? 0.6 : 0.35 + 0.65 * Math.pow(fade(frac(t / (2 * B) - i / 7)), 2), R = p.s * (0.48 + 0.14 * i) * (0.97 + 0.03 * b);
        ring(ctx, p.cx, p.cy, R); stroke(ctx, five[i], 0.011 + 0.006 * w, 0.4 + 0.55 * w);
      }
            dot(ctx, p.cx, p.cy, p.s * (0.045 + 0.015 * b)); fill(ctx, k.glow);
    },
  };

  // An empty sky; a rainbow forms in it from nothing and goes back to
  // nothing. Nothing made it, nothing holds it.
  F.dzogchen_rainbow = {
    label: 'a rainbow in open sky', says: 'Dzogchen: like a rainbow in open sky, appearance arising by itself from openness.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const v = still ? 1 : Math.pow(fade(frac(t / (3 * B))), 1.4), five = FIVE(k), x = p.cx, y = p.cy + p.s * 0.75, R = p.s * 1.05;
      soft(ctx, x, y - R * 0.6, p.s * 1.2, k.glow, 0.2 * v);
      for (let i = 0; i < 5; i++) { const M = 60; for (let j = 0; j < M; j++) { const a0 = Math.PI + Math.PI * j / M, ends = Math.pow(Math.sin(Math.PI * (j + 0.5) / M), 0.6); ctx.beginPath(); ctx.arc(x, y, R - i * p.s * 0.055, a0, a0 + Math.PI / M + 0.01); stroke(ctx, five[4 - i], p.s * 0.055, 0.75 * v * ends); } }
    },
  };

  // Whatever arises in the disc — a wave, a scatter, a loop — shows first
  // in its own colour; recognised, it takes the disc's colour and is gone.
  F.mahamudra_recognise = {
    label: 'recognised as mind', says: 'Mahāmudrā: whatever arises is recognised as mind itself, and settles back into it.',
    build: (r, pl) => ({ ...pl, dots: Array.from({ length: 7 }, () => [r.range(-0.4, 0.4), r.range(-0.3, 0.3)]) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.85, h = still ? 0.42 : frac(t / (3 * B)) * 3, i = Math.floor(h), u = h - i;
      const shown = C.ss(0, 0.2, u) * (1 - C.ss(0.7, 0.95, u)), known = C.ss(0.3, 0.55, u), col = mix(k.alt, mix(k.paper, k.main, 0.35), known);
      soft(ctx, p.cx, p.cy, R * 1.5, k.glow, 0.18 + 0.12 * known * shown);
      clearDisc(ctx, p.cx, p.cy, R, k, b);
      ring(ctx, p.cx, p.cy, R * (1 + 0.04 * fade((u - 0.3) / 0.35))); stroke(ctx, k.glow, 0.012, 0.8 * fade((u - 0.3) / 0.35));
      const sc = p.s * (0.9 + 0.1 * shown);
      ctx.beginPath();
      if (i === 0) { for (let j = 0; j <= 40; j++) { const v = j / 40, x = p.cx + (v - 0.5) * sc * 1.0, y = p.cy + Math.sin(v * TAU * 1.5) * sc * 0.14; j ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } stroke(ctx, col, 0.014, shown); }
      else if (i === 1) p.dots.forEach(([dx, dy]) => { dot(ctx, p.cx + dx * sc, p.cy + dy * sc, p.s * 0.045); fill(ctx, col, shown); });
      else { ctx.ellipse(p.cx, p.cy, sc * 0.32, sc * 0.2, 0.4, 0, TAU); stroke(ctx, col, 0.014, shown); }
    },
  };

  // Waves and water: in the clear disc, waves rise and fall back. They
  // are never anything but the water.
  F.mahamudra_waves = {
    label: 'waves are water', says: 'Mahāmudrā: thoughts rise like waves and fall back; they were never other than the water.',
    build: (r, pl) => ({ ...pl, ph: r.range(0, TAU) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.85, rise = still ? 0.7 : Math.pow(fade(frac(t / (2 * B))), 1.5), lvl = p.cy + p.s * 0.08;
      clearDisc(ctx, p.cx, p.cy, R, k, b);
      ctx.save(); dot(ctx, p.cx, p.cy, R * 0.99); ctx.clip();
      ctx.beginPath(); ctx.moveTo(p.cx - R, p.cy + R);
      for (let j = 0; j <= 80; j++) { const v = j / 80, x = p.cx + (v - 0.5) * 2 * R, crest = Math.exp(-Math.pow((v - 0.5) / 0.3, 2)); ctx.lineTo(x, lvl - p.s * (0.03 + 0.2 * rise * crest) * (0.5 + 0.5 * Math.cos(TAU * (v - 0.5) * 2.5 + (still ? 0 : t * 0.3))) + p.s * 0.02 * Math.sin(TAU * v * 3 + p.ph + (still ? 0 : t * 0.5))); }
      ctx.lineTo(p.cx + R, p.cy + R); ctx.closePath(); fill(ctx, mix(k.main, k.paper, 0.45), 0.85);
      ctx.restore();
      ring(ctx, p.cx, p.cy, R); stroke(ctx, k.main, 0.006, 0.5);
    },
  };

  // One taste: shapes of every kind and colour drift in, lose their
  // difference, and are one light at the centre.
  F.mahamudra_taste = {
    label: 'one taste', says: 'Mahāmudrā: every kind of experience, met fully, has one taste — the mind’s own.',
    build: (r, pl) => ({ ...pl, items: Array.from({ length: 6 }, (_, i) => ({ a: TAU * i / 6 + r.range(-0.3, 0.3), ph: i / 6, kind: i % 3 })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), five = FIVE(k), core = mix(k.glow, '#FFFFFF', 0.3);
      soft(ctx, p.cx, p.cy, p.s * (0.9 + 0.15 * b), k.glow, 0.45);
      p.items.forEach((q, i) => {
        const u = still ? frac(q.ph + 0.3) : frac(t / (3 * B) + q.ph), d = p.s * 1.15 * (1 - Math.pow(u, 1.6)), x = p.cx + Math.cos(q.a + u * 0.8) * d, y = p.cy + Math.sin(q.a + u * 0.8) * d;
        const same = C.ss(0.35, 0.9, u), col = mix(five[1 + (i % 4)], core, same), a = C.ss(0, 0.12, u) * (1 - C.ss(0.9, 1, u)), z = p.s * 0.1 * (1 - 0.5 * same);
        ctx.beginPath();
        if (q.kind === 0 || same > 0.8) { dot(ctx, x, y, z * 0.7); fill(ctx, col, a); }
        else if (q.kind === 1) { ring(ctx, x, y, z); stroke(ctx, col, 0.01, a); }
        else { for (let j = 0; j <= 16; j++) { const v = j / 16; const xx = x + (v - 0.5) * z * 3 * (1 - same), yy = y + Math.sin(v * TAU) * z * 0.6 * (1 - same); j ? ctx.lineTo(xx, yy) : ctx.moveTo(xx, yy); } stroke(ctx, col, 0.011, a); }
      });
      dot(ctx, p.cx, p.cy, p.s * (0.2 + 0.03 * b)); fill(ctx, core, 0.95);
    },
  };

  // ================= Trāṭaka and Kasiṇa =================
  const tear = (ctx, x, y, h, w) => { ctx.beginPath(); ctx.moveTo(x, y - h); ctx.bezierCurveTo(x + w * 0.9, y - h * 0.35, x + w, y + h * 0.2, x, y + h * 0.3); ctx.bezierCurveTo(x - w, y + h * 0.2, x - w * 0.9, y - h * 0.35, x, y - h); };
  // Eyes closing, without eyes: the dark closes in from the edges.
  function closeIn(ctx, p, col, a) { if (a <= 0) return; const g = ctx.createRadialGradient(p.cx, p.cy, p.s * 0.2, p.cx, p.cy, p.s * 2); g.addColorStop(0, css(col, a * 0.55)); g.addColorStop(0.5, css(col, a * 0.85)); g.addColorStop(1, css(col, a)); ctx.fillStyle = g; ctx.fillRect(p.cx - 2, p.cy - 2, 4, 4); }

  // Gazing at the flame without blinking; then the dark closes in, and the
  // flame is still there inside, pale and cool, drifting, fading.
  F.trataka_after = {
    label: 'flame, then afterimage', says: 'Trāṭaka: gazing at one flame, then holding its afterimage, pale and cool, within.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.3 : frac(t / (2 * B)), shut = C.ss(0.44, 0.62, u) * (1 - C.ss(0.84, 1, u)), ghost = C.ss(0.58, 0.68, u) * (1 - C.ss(0.76, 0.9, u));
      const flick = still ? 0 : (0.015 * S(t, 2.3) + 0.008 * S(t, 0.9)) * (1 - shut), fy = p.cy - p.s * 0.12, fx = p.cx + flick * p.s;
      const seen = 1 - shut; // eyes closed, the flame itself is gone
      soft(ctx, p.cx, fy, p.s * 1.0, k.glow, 0.5 * seen);
      tear(ctx, fx, fy, p.s * 0.52, p.s * 0.21); fill(ctx, k.alt, seen);
      tear(ctx, fx, fy + p.s * 0.09, p.s * 0.26, p.s * 0.09); fill(ctx, k.glow, seen);
      ctx.beginPath(); ctx.moveTo(p.cx, fy + p.s * 0.16); ctx.lineTo(p.cx, fy + p.s * 0.3); stroke(ctx, k.line, 0.008, seen);
      ctx.beginPath(); ctx.roundRect(p.cx - p.s * 0.15, fy + p.s * 0.3, p.s * 0.3, p.s * 0.72, p.s * 0.03); fill(ctx, k.main, 0.9 * seen);
      closeIn(ctx, p, mix(k.paper, '#000000', 0.45), shut * 0.96);
      if (ghost > 0) { const gy = fy - p.s * 0.12 * (u - 0.6), cool = mix(k.main, k.paper, 0.15); soft(ctx, p.cx, gy, p.s * 0.6, cool, 0.3 * ghost); tear(ctx, p.cx, gy, p.s * 0.48, p.s * 0.2); fill(ctx, cool, 0.6 * ghost); }
    },
  };

  // Gazing at one black point; then, eyes closed, the same point shows as
  // light in the dark: the afterimage is the negative.
  F.trataka_point = {
    label: 'one point, then its light', says: 'Trāṭaka: gazing at one dark point, then seeing it within as a point of light.',
    build: (r, pl) => ({ ...pl, rays: Array.from({ length: 10 }, (_, i) => TAU * i / 10 + r.range(-0.1, 0.1)) }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.25 : frac(t / (2 * B)), shut = C.ss(0.42, 0.6, u) * (1 - C.ss(0.84, 1, u)), ghost = C.ss(0.56, 0.66, u) * (1 - C.ss(0.74, 0.88, u)), gaze = C.ss(0, 0.3, u);
      p.rays.forEach((a) => { const r0 = p.s * lerp(1.3, 0.28, gaze), r1 = p.s * 1.4; ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0); ctx.lineTo(p.cx + Math.cos(a) * r1, p.cy + Math.sin(a) * r1); stroke(ctx, k.main, 0.005, 0.35 * (1 - shut)); });
      dot(ctx, p.cx, p.cy, p.s * 0.1); fill(ctx, k.main);
      closeIn(ctx, p, isLight(k) ? mix(k.main, k.paper, 0.15) : mix(k.paper, '#000000', 0.5), shut * 0.97);
      if (ghost > 0) { soft(ctx, p.cx, p.cy, p.s * 0.45, k.glow, 0.55 * ghost); dot(ctx, p.cx, p.cy, p.s * 0.1); fill(ctx, mix(k.glow, '#FFFFFF', 0.4), ghost); }
    },
  };

  // The flame steadies as the gaze steadies: its sway dies away over a
  // long while, its reflection in the dark beneath goes still, then stirs.
  F.trataka_still = {
    label: 'a steadying flame', says: 'Trāṭaka: as the gaze steadies, the flame and the mind steady together.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const calm = still ? 1 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), sway = (1 - calm) * (still ? 0 : 0.06 * S(t, 2.1) + 0.03 * S(t, 0.77, 1)), fy = p.cy - p.s * 0.1, wy = p.cy + p.s * 0.5;
      soft(ctx, p.cx, fy, p.s * 0.9, k.glow, 0.45 + 0.15 * calm);
      ctx.save(); ctx.translate(p.cx, fy + p.s * 0.3); ctx.rotate(sway); ctx.translate(-p.cx, -(fy + p.s * 0.3));
      tear(ctx, p.cx, fy, p.s * 0.55, p.s * 0.2); fill(ctx, k.alt);
      tear(ctx, p.cx, fy + p.s * 0.1, p.s * 0.26, p.s * 0.085); fill(ctx, k.glow);
      ctx.restore();
      ctx.beginPath(); ctx.moveTo(p.cx, fy + p.s * 0.18); ctx.lineTo(p.cx, fy + p.s * 0.34); stroke(ctx, k.line, 0.008);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.2, wy); ctx.lineTo(p.cx + p.s * 1.2, wy); stroke(ctx, k.main, 0.005, 0.4);
      for (let i = 0; i < 5; i++) { const y = wy + p.s * (0.1 + i * 0.09), w = p.s * (0.22 - i * 0.03) * (1 + (1 - calm) * (still ? 0 : 0.5 * S(t, 1.7 + i * 0.4, i))); pill(ctx, p.cx + (1 - calm) * p.s * 0.06 * (still ? 0 : S(t, 2.3 + i * 0.3, i)), y, w, p.s * 0.035, 0); fill(ctx, k.alt, 0.55 - i * 0.09); }
    },
  };

  // An earth kasiṇa, the colour of dawn: at first a copy with every flaw
  // (the learning sign), it slowly becomes the counterpart sign —
  // smooth, bright, flawless, “like the moon coming out from a cloud”.
  F.kasina_earth = {
    label: 'the sign comes clear', says: 'Kasiṇa: a disc of dawn-coloured clay, gazed at until its flawless bright sign appears.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.68, 1.6, 0), flaws: Array.from({ length: 70 }, () => { const a = r.range(0, TAU), d = Math.sqrt(r.next()) * 0.6; return [Math.cos(a) * d, Math.sin(a) * d, r.range(0.01, 0.03)]; }) }),
    draw(ctx, p, k, t, still) {
      const pure = still ? 0.45 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), b = BR(t, still), clay = mix(k.alt, k.main, 0.4), bright = mix(k.glow, '#FFFFFF', 0.45), col = mix(clay, bright, C.ss(0.2, 0.95, pure));
      soft(ctx, p.cx, p.cy, p.s * (1.0 + 0.3 * pure), k.glow, 0.15 + 0.5 * pure);
      C.blobPath(ctx, p.blob, { imperf: 1 - pure, grow: 0.97 + 0.03 * b }); fill(ctx, col);
      p.flaws.forEach(([x, y, z]) => { dot(ctx, p.cx + x * p.s, p.cy + y * p.s, p.s * z); fill(ctx, mix(clay, k.main, 0.5), 0.75 * (1 - C.ss(0, 0.7, pure))); });
    },
  };

  // The fire kasiṇa as the texts set it up: a mat with a round hole, and
  // the fire seen only through the hole, a disc of flame.
  F.kasina_fire = {
    label: 'fire through the hole', says: 'Kasiṇa: fire seen through a round hole in a mat, so the eye holds only a disc of flame.',
    build: (r, pl) => ({ ...pl, fire: { ...Prims.fire.build(r, { cx: pl.cx, cy: pl.cy - pl.s * 0.1, s: pl.s * 0.48 }), kind: 'tongues', log: false } }),
    draw(ctx, p, k, t, still) {
      const R = p.s * 0.52, b = BR(t, still);
      ctx.save(); dot(ctx, p.cx, p.cy, R); ctx.clip();
      ctx.fillStyle = css(mix(k.alt, k.paper, 0.35)); ctx.fillRect(p.cx - R, p.cy - R, 2 * R, 2 * R);
      Prims.fire.draw(ctx, p.fire, { ...k, main: k.alt, alt: mix(k.glow, '#FFFFFF', 0.3), line: k.alt }, t, still);
      ctx.restore();
      soft(ctx, p.cx, p.cy, R * (1.6 + 0.1 * b), k.glow, 0.28);
      C.cutPoly(ctx, [[p.cx - p.s * 1.0, p.cy - p.s * 0.95], [p.cx + p.s * 1.02, p.cy - p.s * 0.98], [p.cx + p.s * 0.98, p.cy + p.s * 0.96], [p.cx - p.s * 1.03, p.cy + p.s * 0.98]], C.makeRng('mat'), 0.006);
      ctx.moveTo(p.cx + R, p.cy); ctx.arc(p.cx, p.cy, R, 0, TAU, true); fill(ctx, mix(k.paper, k.main, 0.22), 0.96);
      ring(ctx, p.cx, p.cy, R); stroke(ctx, k.glow, 0.008, 0.5 + 0.2 * b);
    },
  };

  // The counterpart sign extended: the bright disc grows past each mark,
  // past the edge, till there is nothing but its light; then gathers.
  F.kasina_extend = {
    label: 'the sign extended', says: 'Kasiṇa: the bright sign extended, a hand’s breadth, then further, until it fills everything.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.35 : 0.5 - 0.5 * Math.cos(TAU * t / (3 * B)), R = p.s * lerp(0.28, 3.2, Math.pow(u, 1.6)), col = mix(k.glow, '#FFFFFF', 0.35);
      [0.45, 0.8, 1.15].forEach((m) => { ring(ctx, p.cx, p.cy, p.s * m); stroke(ctx, k.main, 0.004, 0.4 * (1 - C.ss(m * 0.8, m * 1.05, R / p.s))); });
      const g = ctx.createRadialGradient(p.cx, p.cy, 0, p.cx, p.cy, R * 1.25); g.addColorStop(0, css(col, 0.98)); g.addColorStop(0.78, css(col, 0.95)); g.addColorStop(1, css(col, 0));
      ctx.fillStyle = g; dot(ctx, p.cx, p.cy, R * 1.25); ctx.fill();
      dot(ctx, p.cx, p.cy, p.s * 0.04); fill(ctx, k.alt, 0.8);
    },
  };

  return F;
})();
