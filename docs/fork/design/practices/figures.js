/* Practice figures: one per practice, each saying something true about it.
 *
 * Same contract as round 4's prims.js, so Phase 2 can port them beside the
 * Dart engine's figures:
 *   { label, says, build(r, place), draw(ctx, p, k, t, still) }
 *   place { cx, cy, s } in the unit square; inks k { paper, main, alt, line, glow }.
 * Every figure loops without a seam, breath-paced where it fits (Core.BREATH,
 * 10 s), and has a calm still frame for lists and reduced motion. Three reuse
 * round 4's primitives as they are (breath, grass, lotus inside `image`). */
const Practices = (() => {
  'use strict';
  const C = Core, { TAU, lerp, css, mix, clamp } = C;
  const B = C.BREATH;
  const S = (t, per, ph = 0) => Math.sin(TAU * t / per + ph);
  const BR = (t, still, ph = 0) => (still ? 0.5 : 0.5 - 0.5 * Math.cos(TAU * t / B + ph)); // 0..1 on the breath
  const fade = (u) => Math.sin(Math.PI * clamp(u, 0, 1));
  const frac = (x) => x - Math.floor(x);
  const fill = (ctx, col, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = css(col); ctx.fill(); ctx.globalAlpha = 1; };
  // lineWidth 0 is ignored by canvas (the previous width stays), so never set it.
  const stroke = (ctx, col, w, a = 1) => { ctx.globalAlpha = a; ctx.strokeStyle = css(col); ctx.lineWidth = Math.max(w, 1e-4); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); ctx.globalAlpha = 1; };
  const soft = (ctx, x, y, r, col, a) => { if (r <= 0) return; const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  const dot = (ctx, x, y, r) => { ctx.beginPath(); ctx.arc(x, y, Math.max(r, 0), 0, TAU); };
  const ring = (ctx, x, y, r) => { ctx.beginPath(); ctx.arc(x, y, Math.max(r, 0), 0, TAU); };

  // A sitter, as three soft forms: seat, body, head. Parts can be left out.
  function sitter(ctx, cx, cy, s, o = {}) {
    const top = cy - 0.12 * s, hip = cy + 0.42 * s;
    ctx.beginPath();
    ctx.moveTo(cx - 0.62 * s, cy + 0.62 * s);
    ctx.bezierCurveTo(cx - 0.66 * s, cy + 0.44 * s, cx - 0.48 * s, cy + 0.4 * s, cx - 0.4 * s, hip);
    ctx.bezierCurveTo(cx - 0.36 * s, cy + 0.1 * s, cx - 0.36 * s, top, cx - 0.2 * s, top - 0.04 * s);
    ctx.quadraticCurveTo(cx, top - 0.1 * s, cx + 0.2 * s, top - 0.04 * s);
    ctx.bezierCurveTo(cx + 0.36 * s, top, cx + 0.36 * s, cy + 0.1 * s, cx + 0.4 * s, hip);
    ctx.bezierCurveTo(cx + 0.48 * s, cy + 0.4 * s, cx + 0.66 * s, cy + 0.44 * s, cx + 0.62 * s, cy + 0.62 * s);
    ctx.quadraticCurveTo(cx, cy + 0.74 * s, cx - 0.62 * s, cy + 0.62 * s);
    ctx.closePath();
    if (o.body !== false) fill(ctx, o.col, o.a ?? 1);
    if (o.head !== false) { dot(ctx, cx, cy - 0.38 * s, 0.17 * s); fill(ctx, o.col, o.a ?? 1); }
  }
  const nz = (p) => p._nz || Object.defineProperty(p, '_nz', { value: C.noise1(C.makeRng(String(p.nzSeed)), 2), enumerable: false })._nz;

  const F = {};

  // ---------------- heart ----------------
  F.metta = {
    label: 'widening rings', says: 'Kindness starts close and widens until no one is outside it.',
    build: (r, pl) => ({ ...pl, n: 5 }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B;
      soft(ctx, p.cx, p.cy, p.s * 0.55, k.glow, 0.55);
      for (let i = 0; i < p.n; i++) {
        const u = frac((still ? 0.15 : t / per) + i / p.n), r = p.s * (0.14 + 1.15 * C.easeOut(u));
        ring(ctx, p.cx, p.cy, r); stroke(ctx, k.main, 0.006 + 0.008 * (1 - u), 0.85 * fade(u * 1.05));
      }
      dot(ctx, p.cx, p.cy, p.s * (0.12 + 0.02 * BR(t, still))); fill(ctx, k.alt);
    },
  };

  F.tonglen = {
    label: 'taking in, sending out', says: 'Breathing in what hurts, breathing out ease: karuṇā as tonglen.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const ph = still ? 0.3 : frac(t / B), inhale = ph < 0.5, u = inhale ? ph * 2 : (ph - 0.5) * 2;
      // in-breath: a dark ring closes in; out-breath: a light ring opens out
      if (inhale) { ring(ctx, p.cx, p.cy, p.s * lerp(1.15, 0.3, C.easeInOut(u))); stroke(ctx, k.line, 0.03 * (1 - u) + 0.006, 0.55 * fade(u)); }
      else { ring(ctx, p.cx, p.cy, p.s * lerp(0.3, 1.2, C.easeOut(u))); stroke(ctx, k.glow, 0.022 * (1 - u) + 0.004, 0.8 * fade(u)); soft(ctx, p.cx, p.cy, p.s * lerp(0.3, 1.1, u), k.glow, 0.25 * (1 - u)); }
      soft(ctx, p.cx, p.cy, p.s * 0.5, k.glow, 0.4);
      dot(ctx, p.cx, p.cy, p.s * 0.26); fill(ctx, k.main);
      dot(ctx, p.cx - p.s * 0.06, p.cy - p.s * 0.07, p.s * 0.07); fill(ctx, k.glow, 0.7);
    },
  };

  F.knot = {
    label: 'a knot loosening', says: 'Forgiveness loosens what has been held tight.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const L = still ? 0.35 : 0.5 + 0.5 * S(t, 2 * B, -Math.PI / 2); // 0 tight, 1 open
      const M = 260, loops = lerp(2.5, 0.0, L), R = p.s * lerp(0.62, 0.9, L);
      soft(ctx, p.cx, p.cy, p.s * (0.4 + 0.6 * L), k.glow, 0.15 + 0.35 * L);
      ctx.beginPath();
      for (let i = 0; i <= M; i++) {
        const u = i / M, x0 = p.cx + p.s * lerp(-1.15, 1.15, u), env = Math.sin(Math.PI * u);
        // a rope that winds round itself when tight, and lies as one easy wave when let go
        const a = TAU * (loops + 0.5) * u;
        const x = x0 - R * 0.95 * env * env * Math.sin(a) * (1 - L * 0.85);
        const y = p.cy + R * 0.6 * env * env * Math.cos(a) * (1 - L) + p.s * 0.18 * L * Math.sin(TAU * u);
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      stroke(ctx, k.main, 0.022);
      dot(ctx, p.cx - p.s * 1.1, p.cy, p.s * 0.035); fill(ctx, k.alt);
      dot(ctx, p.cx + p.s * 1.1, p.cy, p.s * 0.035); fill(ctx, k.alt);
    },
  };

  F.dyad = {
    label: 'two in dialogue', says: 'Two people meditating together; what arises lives between them.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const lean = BR(t, still), d = p.s * lerp(0.62, 0.48, lean), r = p.s * 0.48;
      const speak = still ? 0 : S(t, B * 1.2); // turns: one voice, then the other
      [-1, 1].forEach((sd) => {
        ring(ctx, p.cx + sd * d, p.cy, r); fill(ctx, k.main, 0.16); stroke(ctx, k.main, 0.012, 0.85);
        const on = clamp(sd * speak, 0, 1);
        for (let i = 1; i <= 2; i++) { ctx.beginPath(); ctx.arc(p.cx + sd * d, p.cy, r + p.s * 0.09 * i, sd > 0 ? Math.PI * 0.82 : -Math.PI * 0.18, sd > 0 ? Math.PI * 1.18 : Math.PI * 0.18); stroke(ctx, k.alt, 0.008, 0.6 * on / i); }
      });
      // the shared lens between them
      ctx.save(); ring(ctx, p.cx - d, p.cy, r); ctx.clip(); ring(ctx, p.cx + d, p.cy, r); fill(ctx, k.alt, 0.35 + 0.35 * lean); ctx.restore();
    },
  };

  F.seed = {
    label: 'a planted resolve', says: 'A saṅkalpa is a seed planted in deep rest, then tended.',
    build: (r, pl) => ({ ...pl, lean: r.range(-0.12, 0.12) }),
    draw(ctx, p, k, t, still) {
      const g = p.cy + p.s * 0.55, sway = still ? 0 : 0.05 * S(t, B), grow = 0.92 + 0.08 * BR(t, still);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.1, g); ctx.quadraticCurveTo(p.cx, g - p.s * 0.06, p.cx + p.s * 1.1, g); stroke(ctx, k.line, 0.01, 0.7);
      ctx.beginPath(); ctx.ellipse(p.cx, g + p.s * 0.12, p.s * 0.13, p.s * 0.09, 0.3, 0, TAU); fill(ctx, k.alt);
      const tx = p.cx + p.s * (p.lean + sway), ty = g - p.s * 0.95 * grow;
      ctx.beginPath(); ctx.moveTo(p.cx, g + p.s * 0.05); ctx.quadraticCurveTo(p.cx + p.s * 0.02, g - p.s * 0.5, tx, ty); stroke(ctx, k.main, 0.014);
      [[-1, 0.55], [1, 0.75]].forEach(([sd, at]) => {
        const lx = lerp(p.cx, tx, at), ly = lerp(g, ty, at), a = -Math.PI / 2 + sd * (0.9 + 0.1 * BR(t, still));
        ctx.save(); ctx.translate(lx, ly); ctx.rotate(a + Math.PI / 2);
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.quadraticCurveTo(sd * p.s * 0.16, -p.s * 0.08, sd * p.s * 0.3, 0); ctx.quadraticCurveTo(sd * p.s * 0.16, p.s * 0.07, 0, 0); fill(ctx, k.main);
        ctx.restore();
      });
      soft(ctx, tx, ty, p.s * 0.22, k.glow, 0.5);
    },
  };

  // ---------------- concentration ----------------
  F.stillwater = {
    label: 'water settling', says: 'Samatha: the ripples calm until the water holds one clear point.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B, u = still ? 0.9 : frac(t / per), calm = C.easeOut(u);
      for (let i = 0; i < 4; i++) {
        const rr = p.s * (0.25 + 0.28 * i + 0.18 * u);
        ctx.beginPath(); ctx.ellipse(p.cx, p.cy + p.s * 0.2, rr, rr * 0.28, 0, 0, TAU);
        stroke(ctx, k.main, 0.008, (1 - calm) * 0.7 * (1 - i / 4) + 0.08);
      }
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.2, p.cy + p.s * 0.2); ctx.lineTo(p.cx + p.s * 1.2, p.cy + p.s * 0.2); stroke(ctx, k.line, 0.006, 0.3 + 0.4 * calm);
      const y = p.cy - p.s * 0.35 - p.s * 0.03 * (1 - calm) * S(t, 1.7);
      soft(ctx, p.cx, y, p.s * 0.3, k.glow, 0.35 + 0.3 * calm);
      dot(ctx, p.cx, y, p.s * 0.08); fill(ctx, k.alt);
      ctx.beginPath(); ctx.ellipse(p.cx, p.cy + p.s * 0.2 + (p.cy + p.s * 0.2 - y) * 0.6, p.s * 0.06, p.s * 0.02, 0, 0, TAU); fill(ctx, k.alt, 0.25 + 0.4 * calm);
    },
  };

  F.absorption = {
    label: 'light gathering in', says: 'Jhāna: scattered joy gathers into one bright, still centre.',
    build: (r, pl) => ({ ...pl, motes: Array.from({ length: 26 }, () => ({ a: r.range(0, TAU), d: r.range(0.7, 1.25), ph: r.next(), sz: r.range(0.02, 0.04) })) }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B;
      p.motes.forEach((m) => {
        const u = still ? m.ph : frac(t / per + m.ph), rr = p.s * m.d * (1 - C.easeInOut(u) * 0.85), a = m.a + u * 0.6;
        dot(ctx, p.cx + Math.cos(a) * rr, p.cy + Math.sin(a) * rr, p.s * m.sz * (1 - 0.5 * u)); fill(ctx, k.alt, 0.85 * fade(u));
      });
      const b = BR(t, still);
      soft(ctx, p.cx, p.cy, p.s * (0.75 + 0.15 * b), k.glow, 0.5);
      for (let i = 0; i < 12; i++) { const a = TAU * i / 12 + (still ? 0 : t * 0.02); ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * p.s * 0.34, p.cy + Math.sin(a) * p.s * 0.34); ctx.lineTo(p.cx + Math.cos(a) * p.s * (0.48 + 0.08 * b), p.cy + Math.sin(a) * p.s * (0.48 + 0.08 * b)); stroke(ctx, k.main, 0.006, 0.5); }
      dot(ctx, p.cx, p.cy, p.s * (0.26 + 0.03 * b)); fill(ctx, k.main);
      dot(ctx, p.cx, p.cy, p.s * 0.12); fill(ctx, k.glow, 0.8);
    },
  };

  F.breath = {
    label: 'breath', says: 'Ānāpānasati: the breath rising and falling, known all the way through.',
    build: (r, pl) => ({ ...Prims.breath.build(r, pl), kind: 'orb' }),
    draw: (ctx, p, k, t, still) => Prims.breath.draw(ctx, p, k, t, still),
  };

  F.stages = {
    label: 'ten stages', says: 'The Mind Illuminated: ten stages, climbed one at a time.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 4 * B, u = still ? 0.72 : frac(t / per), at = u * 10;
      for (let i = 0; i < 10; i++) {
        const a = Math.PI * (1.05 - 0.1 * i / 9) - Math.PI * 0.95 * (i / 9), x = p.cx + Math.cos(a) * p.s * 0.95, y = p.cy + p.s * 0.45 - Math.sin(a) * p.s * 1.0 + p.s * 0.0;
        const lit = clamp(at - i, 0, 1), sz = p.s * (0.05 + 0.035 * i / 9);
        dot(ctx, x, y, sz); fill(ctx, k.main, 0.25 + 0.75 * lit);
        if (i === Math.floor(at)) soft(ctx, x, y, sz * 4, k.glow, 0.6 * fade(frac(at)));
      }
      ctx.beginPath(); ctx.arc(p.cx, p.cy + p.s * 0.45, p.s * 0.95, Math.PI * 1.05, Math.PI * 1.95); stroke(ctx, k.line, 0.005, 0.3);
    },
  };

  F.flame = {
    label: 'one steady flame', says: 'Trāṭaka: gazing at one flame, then holding its afterimage within.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B, u = still ? 0.2 : frac(t / per), gaze = u < 0.6, ghost = gaze ? 0 : fade((u - 0.6) / 0.4);
      const flick = still ? 0 : 0.02 * S(t, 2.3) + 0.01 * S(t, 0.9);
      const tear = (x, y, h, w) => { ctx.beginPath(); ctx.moveTo(x, y - h); ctx.bezierCurveTo(x + w * 0.9, y - h * 0.35, x + w, y + h * 0.2, x, y + h * 0.3); ctx.bezierCurveTo(x - w, y + h * 0.2, x - w * 0.9, y - h * 0.35, x, y - h); };
      const fx = p.cx + flick * p.s, fy = p.cy - p.s * 0.05;
      soft(ctx, p.cx, fy, p.s * 0.9, k.glow, 0.45 * (1 - ghost * 0.6));
      tear(fx, fy, p.s * 0.5, p.s * 0.2); fill(ctx, k.alt, 1 - ghost * 0.7);
      tear(fx, fy + p.s * 0.08, p.s * 0.25, p.s * 0.09); fill(ctx, k.glow, 1 - ghost * 0.7);
      ctx.beginPath(); ctx.roundRect(p.cx - p.s * 0.16, fy + p.s * 0.25, p.s * 0.32, p.s * 0.65, p.s * 0.03); fill(ctx, k.main, 1 - ghost * 0.8);
      ctx.beginPath(); ctx.moveTo(p.cx, fy + p.s * 0.25); ctx.lineTo(p.cx, fy + p.s * 0.12); stroke(ctx, k.line, 0.008, 1 - ghost);
      // the afterimage: the same flame, in the other ink, held with eyes closed
      if (ghost > 0) { tear(p.cx, fy, p.s * 0.5, p.s * 0.2); fill(ctx, k.main, 0.45 * ghost); soft(ctx, p.cx, fy, p.s * 0.6, k.main, 0.25 * ghost); }
    },
  };

  F.jewels = {
    label: 'three jewels', says: 'Anussati: recollecting the Buddha, the Dhamma and the Saṅgha, one by one.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B;
      [[0, -0.42], [-0.44, 0.34], [0.44, 0.34]].forEach(([dx, dy], i) => {
        const x = p.cx + dx * p.s, y = p.cy + dy * p.s, on = still ? (i === 0 ? 1 : 0.3) : 0.3 + 0.7 * Math.pow(fade(frac(t / per - i / 3) * 1.5), 2);
        soft(ctx, x, y, p.s * 0.45, k.glow, 0.5 * on);
        ctx.beginPath(); ctx.moveTo(x, y - p.s * 0.24); ctx.lineTo(x + p.s * 0.18, y); ctx.lineTo(x, y + p.s * 0.24); ctx.lineTo(x - p.s * 0.18, y); ctx.closePath();
        fill(ctx, i === 0 ? k.alt : k.main, 0.4 + 0.6 * on); stroke(ctx, k.line, 0.006, 0.6);
      });
    },
  };

  // ---------------- insight ----------------
  F.arising = {
    label: 'arising and passing', says: 'Vipassanā: each thing seen arising, staying a moment, passing.',
    build: (r, pl) => ({ ...pl, pts: Array.from({ length: 22 }, () => ({ x: r.range(-1, 1), y: r.range(-0.9, 0.9), ph: r.next(), per: r.range(4, 9), sz: r.range(0.04, 0.11) })).filter((q) => Math.hypot(q.x, q.y) < 1.05) }),
    draw(ctx, p, k, t, still) {
      p.pts.forEach((q, i) => {
        const u = still ? q.ph : frac(t / q.per + q.ph), life = fade(u), x = p.cx + q.x * p.s, y = p.cy + q.y * p.s;
        dot(ctx, x, y, p.s * q.sz * (0.4 + 0.6 * life)); fill(ctx, i % 5 === 0 ? k.alt : k.main, 0.9 * life);
        if (u > 0.5) { ring(ctx, x, y, p.s * q.sz * (1 + 2 * (u - 0.5))); stroke(ctx, k.main, 0.004, 0.5 * (1 - u) * 2); }
      });
    },
  };

  F.notes = {
    label: 'light notes', says: 'Noting: a soft label for each thing as it comes — rising, falling, hearing.',
    build: (r, pl) => ({ ...pl, rows: [0, 1, 2].map(() => Array.from({ length: 7 }, () => ({ w: r.range(0.08, 0.2), gap: r.range(0.05, 0.1) }))) }),
    draw(ctx, p, k, t, still) {
      const per = 2.2, n = 21, now = still ? 13 : (t / per) % n;
      let idx = 0;
      p.rows.forEach((row, ri) => {
        let x = p.cx - p.s * 1.0; const y = p.cy + (ri - 1) * p.s * 0.42;
        row.forEach((m) => {
          const age = (now - idx + n) % n, a = age < 1 ? C.easeOut(age) : Math.max(0.1, 1 - (age - 1) / 8);
          if (x + m.w * p.s <= p.cx + p.s * 1.05) { ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + m.w * p.s * (age < 1 ? C.easeOut(age) : 1), y); stroke(ctx, age < 1 ? k.alt : k.main, 0.022, a); }
          x += (m.w + m.gap) * p.s; idx++;
        });
      });
      const ri = Math.floor(now / 7) % 3;
      soft(ctx, p.cx, p.cy + (ri - 1) * p.s * 0.42, p.s * 0.5, k.glow, 0.18);
    },
  };

  F.empty = {
    label: 'an open circle', says: 'Śūnyatā: a form, and the openness that it is.',
    build: (r, pl) => ({ ...pl, gaps: Array.from({ length: 5 }, () => ({ a: r.range(0, TAU), w: r.range(0.2, 0.5), sp: r.range(0.01, 0.03) * (r.chance(0.5) ? 1 : -1) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.95;
      soft(ctx, p.cx, p.cy, R * 0.95, k.glow, 0.12 + 0.12 * b);
      const M = 240, open = 0.35 + 0.4 * b;
      for (let i = 0; i < M; i++) {
        const a = TAU * i / M;
        let gap = 0;
        p.gaps.forEach((g) => { const d = Math.abs(((a - g.a - (still ? 0 : t * g.sp)) % TAU + TAU + Math.PI) % TAU - Math.PI); gap = Math.max(gap, clamp(1 - d / (g.w * open), 0, 1)); });
        if (gap > 0.95) continue;
        ctx.beginPath(); ctx.arc(p.cx, p.cy, R, a, a + TAU / M + 0.002); stroke(ctx, k.main, 0.016 * (1 - gap), 1 - gap);
      }
    },
  };

  F.wane = {
    label: 'a leaf letting go', says: 'Maraṇasati: everything that lives will fall; remembering it, we wake.',
    build: (r, pl) => ({ ...pl, sway: r.range(0.25, 0.4) }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B, u = still ? 0.35 : frac(t / per), g = p.cy + p.s * 0.8;
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.15, p.cy - p.s * 0.85); ctx.quadraticCurveTo(p.cx - p.s * 0.4, p.cy - p.s * 0.98, p.cx + p.s * 0.2, p.cy - p.s * 0.82); stroke(ctx, k.line, 0.014, 0.8);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.15, g); ctx.lineTo(p.cx + p.s * 1.15, g); stroke(ctx, k.line, 0.006, 0.4);
      const y = lerp(p.cy - p.s * 0.78, g - p.s * 0.05, C.easeInOut(u)), x = p.cx + p.s * (0.05 + p.sway * Math.sin(u * TAU * 1.5)), rot = 0.9 * Math.sin(u * TAU * 1.5) + u * 0.8;
      const a = u < 0.85 ? 1 : 1 - (u - 0.85) / 0.15;
      ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
      ctx.beginPath(); ctx.moveTo(-p.s * 0.2, 0); ctx.quadraticCurveTo(0, -p.s * 0.14, p.s * 0.2, 0); ctx.quadraticCurveTo(0, p.s * 0.14, -p.s * 0.2, 0); fill(ctx, k.alt, a);
      ctx.beginPath(); ctx.moveTo(-p.s * 0.24, 0); ctx.lineTo(p.s * 0.18, 0); stroke(ctx, k.line, 0.004, a * 0.7);
      ctx.restore();
      if (u > 0.85) { ring(ctx, x, g, p.s * 0.3 * (u - 0.85) / 0.15); stroke(ctx, k.main, 0.004, 0.4 * (1 - (u - 0.85) / 0.15)); }
    },
  };

  F.eight = {
    label: 'eight weeks round', says: 'MBSR: an eight-week course, practised day by day.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 4 * B, at = still ? 5.3 : (t / per * 8) % 8;
      ring(ctx, p.cx, p.cy, p.s * 0.8); stroke(ctx, k.line, 0.005, 0.35);
      for (let i = 0; i < 8; i++) {
        const a = -Math.PI / 2 + TAU * i / 8, x = p.cx + Math.cos(a) * p.s * 0.8, y = p.cy + Math.sin(a) * p.s * 0.8, done = i < Math.floor(at), cur = i === Math.floor(at);
        if (cur) soft(ctx, x, y, p.s * 0.3, k.glow, 0.6 * fade(frac(at)));
        dot(ctx, x, y, p.s * (cur ? 0.1 : 0.075)); fill(ctx, cur ? k.alt : k.main, done || cur ? 1 : 0.3);
      }
      Prims.breath.draw(ctx, p._br || Object.defineProperty(p, '_br', { value: { ...Prims.breath.build(C.makeRng('mbsr'), { cx: p.cx, cy: p.cy, s: p.s * 0.42 }), kind: 'orb' }, enumerable: false })._br, k, t, still);
    },
  };

  // ---------------- awareness ----------------
  F.sky = {
    label: 'open sky', says: 'Open awareness: wide space, and weather passing through it.',
    build: (r, pl) => ({ ...pl, clouds: [0, 1, 2].map((i) => ({ y: r.range(-0.75, 0.1), w: r.range(0.35, 0.6), ph: r.next(), per: r.range(38, 60) })) }),
    draw(ctx, p, k, t, still) {
      const hy = p.cy + p.s * 0.62;
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.3, hy); ctx.lineTo(p.cx + p.s * 1.3, hy); stroke(ctx, k.line, 0.006, 0.65);
      p.clouds.forEach((c) => {
        const u = still ? c.ph : frac(t / c.per + c.ph), x = p.cx + p.s * lerp(-1.6, 1.6, u), y = p.cy + c.y * p.s, a = 0.75 * fade(u);
        // soft puffs, lighter than the sky: hard dark ellipses read as stones
        const veil = C.lum(k.paper) > 0.3 ? mix(k.paper, '#FFFFFF', 0.72) : mix(k.paper, k.main, 0.3);
        [[0, 0, 1], [-0.42, 0.07, 0.72], [0.4, 0.08, 0.78], [0.14, -0.12, 0.8], [-0.2, -0.06, 0.7]].forEach(([dx, dy, sc]) => { const rx = c.w * p.s * 0.55 * sc, ry = c.w * p.s * 0.3 * sc; ctx.save(); ctx.translate(x + dx * c.w * p.s, y + dy * c.w * p.s); ctx.scale(1, ry / rx); soft(ctx, 0, 0, rx, veil, a * 0.95); ctx.restore(); });
      });
      dot(ctx, p.cx + p.s * 0.75, hy - p.s * 0.18, p.s * 0.06); fill(ctx, k.alt, 0.9);
    },
  };

  F.enso = {
    label: 'ensō', says: 'Zazen: one breath, one brushstroke; the circle left open.',
    build: (r, pl) => ({ ...pl, start: r.range(-0.4, 0.2), nzSeed: r.next() }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B, u = still ? 0.7 : frac(t / per), drawU = clamp(u / 0.45, 0, 1), hold = u < 0.85 ? 1 : 1 - (u - 0.85) / 0.15;
      const a0 = Math.PI * 0.62 + p.start, sweep = TAU * 0.9 * C.easeInOut(drawU), M = 160, n = nz(p);
      for (let i = 0; i < M; i++) {
        const v = i / M; if (v * TAU * 0.9 > sweep) break;
        const a = a0 + v * TAU * 0.9, rr = p.s * (0.88 + 0.03 * n(v * 7));
        // the tail keeps a visible width at tile size, or the still reads as a crescent
        const w = p.s * (0.12 * Math.pow(1 - v, 0.6) * (0.75 + 0.25 * n(v * 23 + 3)) + 0.04) * (v < 0.04 ? v / 0.04 : 1);
        ctx.beginPath(); ctx.arc(p.cx, p.cy, rr, a, a + TAU * 0.9 / M + 0.01); stroke(ctx, k.main, w, hold * (0.92 - 0.25 * v));
      }
    },
  };

  F.thigle = {
    label: 'a sphere of clear light', says: 'Dzogchen: the mind’s nature, open, clear and already whole.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), cols = [k.main, k.alt, k.glow, k.main, k.alt];
      for (let i = 4; i >= 0; i--) { ring(ctx, p.cx, p.cy, p.s * (0.36 + 0.14 * i) * (0.97 + 0.03 * b)); stroke(ctx, cols[i], 0.04, 0.55 + 0.1 * Math.sin(i + (still ? 0 : t * 0.4))); }
      soft(ctx, p.cx, p.cy, p.s * 0.5, k.paper, 0.9);
      dot(ctx, p.cx, p.cy, p.s * 0.3); fill(ctx, k.paper, 0.6);
      dot(ctx, p.cx, p.cy, p.s * (0.05 + 0.02 * b)); fill(ctx, k.glow);
    },
  };

  F.inquiry = {
    label: 'turning inward', says: 'Ātma-vicāra: “Who am I?” — following attention back to its source.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B, u = still ? 0.55 : frac(t / per), turns = 2.6, M = 220;
      ctx.beginPath();
      for (let i = 0; i <= M; i++) { const v = i / M, a = -TAU * turns * v - (still ? 0 : t * 0.15), rr = p.s * 1.0 * Math.pow(1 - v, 1.15); const x = p.cx + Math.cos(a) * rr, y = p.cy + Math.sin(a) * rr; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      stroke(ctx, k.main, 0.01, 0.75);
      const v = C.easeInOut(u), a = -TAU * turns * v - (still ? 0 : t * 0.15), rr = p.s * Math.pow(1 - v, 1.15);
      dot(ctx, p.cx + Math.cos(a) * rr, p.cy + Math.sin(a) * rr, p.s * 0.06); fill(ctx, k.alt, fade(u));
      soft(ctx, p.cx, p.cy, p.s * 0.35, k.glow, 0.3 + 0.4 * Math.pow(u, 3));
    },
  };

  F.headless = {
    label: 'no head here', says: 'The Headless Way: look back where your head should be — open space, full of the world.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), y = p.cy + p.s * 0.28;
      soft(ctx, p.cx, y - p.s * 0.55, p.s * (0.7 + 0.35 * b), k.glow, 0.45);
      sitter(ctx, p.cx, y, p.s * 0.95, { col: k.main, head: false });
      // where the head would be: a wide opening, the world in it
      ctx.beginPath(); ctx.arc(p.cx, y - p.s * 0.4, p.s * (0.42 + 0.22 * b), Math.PI * 1.08, Math.PI * 1.92); stroke(ctx, k.alt, 0.012, 0.8);
      ctx.beginPath(); ctx.arc(p.cx, y - p.s * 0.4, p.s * (0.7 + 0.25 * b), Math.PI * 1.14, Math.PI * 1.86); stroke(ctx, k.alt, 0.008, 0.45);
    },
  };

  F.glimpse = {
    label: 'a parting cloud', says: 'Effortless mindfulness: a short glimpse of the awareness already here.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B, u = still ? 0.45 : frac(t / per), open = Math.pow(fade(u), 1.5);
      soft(ctx, p.cx, p.cy, p.s * (0.5 + 0.5 * open), k.glow, 0.25 + 0.6 * open);
      dot(ctx, p.cx, p.cy, p.s * 0.12 * open); fill(ctx, k.alt, open);
      [-1, 1].forEach((sd) => {
        const x = p.cx + sd * p.s * (0.38 + 0.5 * open);
        [[0, 0, 1], [0.1, -0.3, 0.75], [-0.05, 0.3, 0.8], [0.25, 0.05, 0.7]].forEach(([dx, dy, sc]) => { ctx.beginPath(); ctx.ellipse(x + sd * dx * p.s, p.cy + dy * p.s, p.s * 0.42 * sc, p.s * 0.3 * sc, 0, 0, TAU); fill(ctx, k.main, 0.85); });
      });
    },
  };

  F.grass = {
    label: 'grass in wind', says: 'Nature: practising outdoors, the land and weather as company.',
    build: (r, pl) => Prims.grass.build(r, { ...pl, cy: pl.cy + pl.s * 0.25 }),
    draw: (ctx, p, k, t, still) => Prims.grass.draw(ctx, p, k, t, still),
  };

  // ---------------- body & energy ----------------
  F.scan = {
    label: 'a slow scan', says: 'Kāyagatāsati: attention moving through the body, part by part.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B, u = still ? 0.35 : 0.5 - 0.5 * Math.cos(TAU * t / per), top = p.cy - p.s * 0.62, bot = p.cy + p.s * 0.98, y = lerp(top, bot, u);
      const cy = p.cy + p.s * 0.18;
      sitter(ctx, p.cx, cy, p.s * 0.95, { col: k.main, a: 0.32 });
      ctx.save(); ctx.beginPath(); ctx.rect(0, y - p.s * 0.12, 1, p.s * 0.24); ctx.clip(); sitter(ctx, p.cx, cy, p.s * 0.95, { col: k.main }); ctx.restore();
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 0.9, y); ctx.lineTo(p.cx + p.s * 0.9, y); stroke(ctx, k.alt, 0.008, 0.9);
      soft(ctx, p.cx, y, p.s * 0.5, k.glow, 0.25);
    },
  };

  F.steps = {
    label: 'footsteps', says: 'Walking: lifting, moving, placing — one step, then the next.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 1.6, n = 7, now = still ? 4.5 : t / per;
      for (let i = 0; i < n; i++) {
        const step = Math.floor(now) - i, age = now - Math.floor(now) + i;
        if (age > n - 0.5) continue;
        const side = step % 2 === 0 ? -1 : 1, v = (step % 40 + 40) % 40;
        const yy = p.cy + p.s * (1.05 - 2.2 * (1 - age / (n - 0.5)));
        const x = p.cx + side * p.s * 0.24 + p.s * 0.08 * Math.sin(v * 0.6);
        const a = (i === 0 ? C.easeOut(frac(now) * 2.5) : 1) * clamp(1 - age / (n - 0.5), 0, 1);
        ctx.save(); ctx.translate(x, yy); ctx.rotate(side * 0.08);
        ctx.beginPath(); ctx.ellipse(0, 0, p.s * 0.13, p.s * 0.23, 0, 0, TAU); fill(ctx, i === 0 ? k.alt : k.main, a);
        ctx.beginPath(); ctx.ellipse(0, p.s * 0.31, p.s * 0.09, p.s * 0.085, 0, 0, TAU); fill(ctx, i === 0 ? k.alt : k.main, a);
        ctx.restore();
      }
    },
  };

  F.flow = {
    label: 'a flowing line', says: 'Qìgōng and yoga: slow movement, breath and attention as one line.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 2 * B, M = 90, head = still ? 0.4 : t / per;
      for (let i = 0; i < M; i++) {
        const v = head - i / M * 0.55, a = TAU * v;
        const x = p.cx + Math.sin(a) * p.s * 0.95, y = p.cy + Math.sin(2 * a) * p.s * 0.42;
        dot(ctx, x, y, p.s * 0.06 * (1 - i / M)); fill(ctx, i < 3 ? k.alt : k.main, 0.9 * (1 - i / M));
      }
      ctx.beginPath();
      for (let i = 0; i <= 120; i++) { const a = TAU * i / 120, x = p.cx + Math.sin(a) * p.s * 0.95, y = p.cy + Math.sin(2 * a) * p.s * 0.42; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      stroke(ctx, k.line, 0.004, 0.3);
    },
  };

  F.field = {
    label: 'a field of energy', says: 'Prāṇa and qì: the body felt as a shimmering field that opens with the breath.',
    build: (r, pl) => ({ ...pl, motes: Array.from({ length: 70 }, () => ({ x: r.range(-0.75, 0.75), y: r.range(-0.75, 0.75), ph: r.range(0, TAU), per: r.range(3, 7) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), cy = p.cy + p.s * 0.2;
      for (let i = 3; i >= 1; i--) { ctx.save(); ctx.translate(p.cx, cy); ctx.scale(1 + 0.12 * i * (0.6 + 0.4 * b), 1 + 0.12 * i * (0.6 + 0.4 * b)); ctx.translate(-p.cx, -cy); sitter(ctx, p.cx, cy, p.s * 0.9, { col: k.glow, a: 0.18 / i }); ctx.restore(); }
      sitter(ctx, p.cx, cy, p.s * 0.9, { col: k.main, a: 0.35 });
      ctx.save(); sitter(ctx, p.cx, cy, p.s * 0.9, { col: k.main, a: 0 }); ctx.clip();
      p.motes.forEach((m) => { const tw = still ? 0.6 : 0.5 + 0.5 * Math.sin(TAU * t / m.per + m.ph); dot(ctx, p.cx + m.x * p.s, cy + m.y * p.s - p.s * 0.1, p.s * 0.025); fill(ctx, k.glow, tw); });
      ctx.restore();
    },
  };

  F.coil = {
    label: 'uncoiling upward', says: 'Kuṇḍalinī: the coiled energy at the base, rising up the spine.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const base = p.cy + p.s * 0.85, top = p.cy - p.s * 0.95, per = 2 * B, u = still ? 0.6 : 0.5 - 0.5 * Math.cos(TAU * t / per), reach = lerp(base, top, u);
      ctx.beginPath(); ctx.moveTo(p.cx, base); ctx.lineTo(p.cx, top); stroke(ctx, k.line, 0.006, 0.35);
      ctx.beginPath();
      for (let i = 0; i <= 80; i++) { const v = i / 80, a = TAU * 2.2 * v, rr = p.s * 0.3 * (1 - v * 0.6); const x = p.cx + Math.cos(a) * rr, y = base - p.s * 0.08 + Math.sin(a) * rr * 0.35 - v * p.s * 0.12; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      stroke(ctx, k.main, 0.014, 0.85);
      ctx.beginPath();
      for (let i = 0; i <= 80; i++) { const v = i / 80, y = lerp(base - p.s * 0.2, reach, v), x = p.cx + p.s * 0.16 * Math.sin(v * TAU * 2.5 - (still ? 0 : t * 0.8)) * (1 - v * 0.4); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      stroke(ctx, k.alt, 0.016, 0.9);
      soft(ctx, p.cx, reach, p.s * 0.35, k.glow, 0.7); dot(ctx, p.cx, reach, p.s * 0.06); fill(ctx, k.glow);
    },
  };

  F.wheels = {
    label: 'seven wheels', says: 'Cakra: wheels of energy along the body’s centre, attended one by one.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const per = 3.5 * B, at = still ? 3.4 : (t / per * 7) % 7;
      ctx.beginPath(); ctx.moveTo(p.cx, p.cy - p.s * 1.0); ctx.lineTo(p.cx, p.cy + p.s * 1.0); stroke(ctx, k.line, 0.005, 0.35);
      for (let i = 0; i < 7; i++) {
        const y = p.cy + p.s * (0.92 - 1.84 * i / 6), lit = Math.max(0, 1 - Math.abs(at - i) * 0.9), r = p.s * (0.11 + 0.04 * lit), rot = (still ? 0 : t * 0.25) * (i % 2 ? 1 : -1);
        if (lit > 0) soft(ctx, p.cx, y, r * 3.2, k.glow, 0.6 * lit);
        ring(ctx, p.cx, y, r); stroke(ctx, lit > 0.5 ? k.alt : k.main, 0.01, 0.6 + 0.4 * lit);
        for (let s = 0; s < 6; s++) { const a = rot + TAU * s / 6; ctx.beginPath(); ctx.moveTo(p.cx, y); ctx.lineTo(p.cx + Math.cos(a) * r, y + Math.sin(a) * r); stroke(ctx, k.main, 0.005, 0.45 + 0.4 * lit); }
      }
    },
  };

  F.rest = {
    label: 'deep rest', says: 'Yoga nidrā: lying down, aware, at the edge of sleep.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), y = p.cy + p.s * 0.45, per = 1.6 * B;
      soft(ctx, p.cx + p.s * 0.55, p.cy - p.s * 0.55, p.s * 0.45, k.glow, 0.4);
      ctx.beginPath(); ctx.arc(p.cx + p.s * 0.55, p.cy - p.s * 0.55, p.s * 0.2, 0, TAU); ctx.arc(p.cx + p.s * 0.63, p.cy - p.s * 0.6, p.s * 0.17, 0, TAU, true); fill(ctx, k.alt);
      dot(ctx, p.cx - p.s * 0.82, y - p.s * 0.06, p.s * 0.13); fill(ctx, k.main);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 0.65, y - p.s * 0.1);
      ctx.bezierCurveTo(p.cx - p.s * 0.3, y - p.s * (0.2 + 0.07 * b), p.cx + p.s * 0.1, y - p.s * (0.18 + 0.04 * b), p.cx + p.s * 0.95, y - p.s * 0.06);
      ctx.lineTo(p.cx + p.s * 0.95, y + p.s * 0.06); ctx.lineTo(p.cx - p.s * 0.65, y + p.s * 0.06); ctx.closePath(); fill(ctx, k.main);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.15, y + p.s * 0.08); ctx.lineTo(p.cx + p.s * 1.15, y + p.s * 0.08); stroke(ctx, k.line, 0.006, 0.5);
      [0, 1, 2].forEach((i) => { const u = still ? 0.3 + i * 0.2 : frac(t / per + i / 3), zx = p.cx - p.s * (0.6 - 0.25 * u), zy = y - p.s * (0.35 + 0.6 * u); dot(ctx, zx, zy, p.s * 0.03 * (1 + i * 0.2)); fill(ctx, k.main, 0.7 * fade(u)); });
    },
  };

  F.feltsense = {
    label: 'a felt sense', says: 'Focusing: a vague, felt something in the body, listened to until it shifts.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy + pl.s * 0.24, pl.s * 0.17, 2.4, 0.004) }),
    draw(ctx, p, k, t, still) {
      const cy = p.cy + p.s * 0.2;
      sitter(ctx, p.cx, cy, p.s * 0.95, { col: k.main, a: 0.35 });
      const imp = still ? 0.8 : 0.5 + 0.5 * S(t, 1.7 * B), grow = 0.9 + 0.15 * BR(t, still);
      soft(ctx, p.cx, p.cy + p.s * 0.24, p.s * 0.42, k.glow, 0.6);
      C.blobPath(ctx, p.blob, { imperf: imp, grow }); fill(ctx, k.alt, 0.92);
    },
  };

  // ---------------- sound & devotion ----------------
  F.chant = {
    label: 'voice in rhythm', says: 'Chanting: the voice carried out in rhythm, together.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const beat = 1.4, x0 = p.cx - p.s * 0.7;
      soft(ctx, x0, p.cy, p.s * 0.35, k.glow, 0.5);
      dot(ctx, x0, p.cy, p.s * 0.1); fill(ctx, k.alt);
      for (let i = 0; i < 5; i++) {
        const u = still ? 0.15 + i * 0.18 : frac(t / (beat * 4) + i / 5), r = p.s * (0.2 + 1.6 * u), w = 0.7 - 0.25 * u;
        ctx.beginPath(); ctx.arc(x0, p.cy, r, -w, w); stroke(ctx, k.main, 0.012 * (1 - u) + 0.004, fade(u) * 0.95);
      }
    },
  };

  F.mala = {
    label: 'beads of a mālā', says: 'Mantra and japa: one repetition, one bead, round and round.',
    build: (r, pl) => ({ ...pl, n: 27 }),
    draw(ctx, p, k, t, still) {
      const at = still ? 9 : Math.floor(t / 1.25) % p.n, R = p.s * 0.85;
      for (let i = 0; i < p.n; i++) {
        const a = Math.PI / 2 + TAU * (i + 0.5) / (p.n + 1), x = p.cx + Math.cos(a) * R, y = p.cy - p.s * 0.05 + Math.sin(a) * R * 0.95, cur = i === at;
        if (cur) soft(ctx, x, y, p.s * 0.22, k.glow, 0.7);
        dot(ctx, x, y, p.s * (cur ? 0.085 : 0.06)); fill(ctx, cur ? k.alt : k.main, i <= at ? 1 : 0.55);
      }
      const gy = p.cy - p.s * 0.05 + R * 0.95;
      dot(ctx, p.cx, gy + p.s * 0.02, p.s * 0.1); fill(ctx, k.alt);
      ctx.beginPath(); ctx.moveTo(p.cx, gy + p.s * 0.1); ctx.lineTo(p.cx - p.s * 0.06, gy + p.s * 0.32); ctx.lineTo(p.cx + p.s * 0.06, gy + p.s * 0.32); ctx.closePath(); fill(ctx, k.alt, 0.8);
    },
  };

  F.offering = {
    label: 'an offering', says: 'Bhakti and pūjā: an offering made, and incense rising.',
    build: (r, pl) => ({ ...pl, nzSeed: r.next() }),
    draw(ctx, p, k, t, still) {
      const by = p.cy + p.s * 0.55, n = nz(p);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 0.55, by - p.s * 0.1); ctx.quadraticCurveTo(p.cx, by + p.s * 0.45, p.cx + p.s * 0.55, by - p.s * 0.1); ctx.closePath(); fill(ctx, k.main);
      ctx.beginPath(); ctx.ellipse(p.cx, by + p.s * 0.28, p.s * 0.2, p.s * 0.04, 0, 0, TAU); fill(ctx, k.main);
      [-0.22, 0, 0.22].forEach((dx, i) => { dot(ctx, p.cx + dx * p.s, by - p.s * (0.16 + (i === 1 ? 0.06 : 0)), p.s * 0.1); fill(ctx, i === 1 ? k.alt : mix(k.alt, k.main, 0.4)); });
      ctx.beginPath(); ctx.moveTo(p.cx + p.s * 0.42, by - p.s * 0.08); ctx.lineTo(p.cx + p.s * 0.52, by - p.s * 0.85); stroke(ctx, k.line, 0.008);
      const tip = [p.cx + p.s * 0.52, by - p.s * 0.85];
      dot(ctx, tip[0], tip[1], p.s * 0.025); fill(ctx, k.glow);
      ctx.beginPath();
      for (let i = 0; i <= 60; i++) { const v = i / 60, y = tip[1] - v * p.s * 1.0, x = tip[0] + p.s * 0.18 * v * Math.sin(v * 5 - (still ? 0 : t * 0.6)) + p.s * 0.08 * n(v * 3 + (still ? 0 : t * 0.05)); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      stroke(ctx, k.main, 0.006, 0.55);
    },
  };

  // ---------------- imagination ----------------
  F.image = {
    label: 'an image forming', says: 'Visualisation: an image gathered from light, held, and let go.',
    build: (r, pl) => ({ ...pl, lotus: Prims.lotus.build(r, { ...pl, s: pl.s * 0.85 }), motes: Array.from({ length: 30 }, () => ({ a: r.range(0, TAU), d: r.range(0.3, 1.1), ph: r.next() })) }),
    draw(ctx, p, k, t, still) {
      const per = 3 * B, u = still ? 0.5 : frac(t / per), form = Math.pow(fade(u), 0.7);
      p.motes.forEach((m) => { const rr = p.s * m.d * (1.3 - form), a = m.a + (still ? 0 : t * 0.05); dot(ctx, p.cx + Math.cos(a) * rr, p.cy + Math.sin(a) * rr * 0.8, p.s * 0.025); fill(ctx, k.alt, 0.8 * (1 - form) + 0.1); });
      soft(ctx, p.cx, p.cy, p.s * 0.9, k.glow, 0.35 * form);
      ctx.save(); ctx.globalAlpha = form; Prims.lotus.draw(ctx, p.lotus, k, t, still); ctx.restore();
    },
  };

  F.soul = {
    label: 'an image with soul', says: 'Soulmaking: an imaginal doorway, warm with meaning, that changes how things look.',
    build: (r, pl) => ({ ...pl, petals: Array.from({ length: 9 }, () => ({ x: r.range(-0.4, 0.4), ph: r.next(), per: r.range(8, 14), sz: r.range(0.04, 0.07) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), w = p.s * 0.62, h = p.s * 1.6, x0 = p.cx - w / 2, y0 = p.cy - h / 2 + p.s * 0.08;
      const arch = () => { ctx.beginPath(); ctx.moveTo(x0, y0 + h); ctx.lineTo(x0, y0 + w / 2); ctx.arc(p.cx, y0 + w / 2, w / 2, Math.PI, 0); ctx.lineTo(x0 + w, y0 + h); ctx.closePath(); };
      arch(); fill(ctx, k.main, 0.22);
      ctx.save(); arch(); ctx.clip();
      soft(ctx, p.cx, y0 + h * 0.42, p.s * (0.55 + 0.15 * b), k.glow, 0.85);
      dot(ctx, p.cx, y0 + h * 0.42, p.s * (0.14 + 0.02 * b)); fill(ctx, k.alt);
      p.petals.forEach((q) => { const u = still ? q.ph : frac(t / q.per + q.ph), x = p.cx + q.x * p.s + p.s * 0.08 * Math.sin(u * TAU * 1.5), y = y0 + h * (0.05 + 0.95 * u); ctx.beginPath(); ctx.ellipse(x, y, p.s * q.sz, p.s * q.sz * 0.5, u * 4, 0, TAU); fill(ctx, k.alt, 0.8 * fade(u)); });
      ctx.restore();
      arch(); stroke(ctx, k.line, 0.012, 0.9);
    },
  };

  return F;
})();
