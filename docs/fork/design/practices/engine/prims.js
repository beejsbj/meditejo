/* Round 4 figures: the strong primitives from round 3, three new ones
 * (flock, petals, grass) and the constellation redone as a scatter of stars
 * whose placement and brightness imply a shape.
 *
 * Every figure moves gracefully: slow, eased, breath-paced where it fits
 * (BREATH = 10 s), looping without a seam (sines, or phases that wrap while
 * faded out). still = a calm frame for lists and reduced motion.
 *
 *   { label, motion, build(r, place, slot), draw(ctx, p, k, t, still) }
 *   place { cx, cy, s }, slot 'figure' | 'accent', inks k { paper, main, alt, line, glow }. */
const Prims = (() => {
  'use strict';
  const C = Core, { TAU, lerp, css, mix } = C;
  const S = (t, period, ph = 0) => Math.sin(TAU * t / period + ph);
  const BR = (t, still, ph = 0) => (still ? 0.5 : 0.5 - 0.5 * Math.cos(TAU * t / C.BREATH + ph)); // 0..1, eased by nature
  const fade = (u) => Math.sin(Math.PI * C.clamp(u, 0, 1)); // 0 at both ends: wraps never pop

  function wobRing(ctx, cx, cy, r, ry, nz, amt) {
    ctx.beginPath();
    const M = Math.max(24, Math.ceil(r * 220));
    for (let i = 0; i <= M; i++) { const a = TAU * i / M, rr = r * (1 + amt * nz(a * 1.3 + r * 9)); const x = cx + rr * Math.cos(a), y = cy + rr * (ry ?? 1) * Math.sin(a); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
  }
  const fill = (ctx, col, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = css(col); ctx.fill(); ctx.globalAlpha = 1; };
  const stroke = (ctx, col, w, a = 1) => { ctx.globalAlpha = a; ctx.strokeStyle = css(col); ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); ctx.globalAlpha = 1; };
  const soft = (ctx, x, y, r, col, a) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  function petal(ctx, x, y, len, wid, ang, bend = 0) {
    const c = Math.cos(ang), s = Math.sin(ang), P = (u, v) => [x + u * c - v * s, y + u * s + v * c];
    const [ax, ay] = P(len, bend * len), [l1x, l1y] = P(len * 0.35, wid), [l2x, l2y] = P(len * 0.8, wid * 0.6 + bend * len * 0.5), [r1x, r1y] = P(len * 0.35, -wid), [r2x, r2y] = P(len * 0.8, -wid * 0.6 + bend * len * 0.5);
    ctx.beginPath(); ctx.moveTo(x, y); ctx.bezierCurveTo(l1x, l1y, l2x, l2y, ax, ay); ctx.bezierCurveTo(r2x, r2y, r1x, r1y, x, y); ctx.closePath();
  }
  function cached(ctx, p, k, paint) {
    const px = Math.round(ctx.getTransform().a), key = `${px}|${C.hex(k.paper)}|${C.hex(k.main)}|${C.hex(k.line)}`;
    if (!p._cache || p._cache.key !== key) {
      const cv = document.createElement('canvas'); cv.width = cv.height = Math.round(px * 1.2);
      const g = cv.getContext('2d'); g.setTransform(px, 0, 0, px, 0.1 * px, 0.1 * px); paint(g);
      Object.defineProperty(p, '_cache', { value: { key, cv }, writable: true, enumerable: false });
    }
    return p._cache.cv;
  }
  // noise functions are rebuilt from a stored seed, so params stay plain data
  const nzOf = (p) => p._nz || Object.defineProperty(p, '_nz', { value: C.noise1(C.makeRng(p.nzSeed), 2), enumerable: false })._nz;

  const P = {};

  P.breath = {
    label: 'breath', motion: 'swells and settles every 10 s, the halo a beat behind',
    build: (r, pl) => ({ ...pl, kind: r.pick(['orb', 'orb', 'lobes']), n: r.int(3, 5), nzSeed: r.next(), blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.55, 0.7, 0.003), tilt: r.range(0.3, 0.55) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      if (p.kind === 'orb') {
        for (let i = p.n - 1; i >= 1; i--) { const bi = BR(t - i * 0.8, still), rr = p.s * (0.5 + 0.5 * (i + 1) / p.n) * (0.86 + 0.14 * bi); wobRing(ctx, p.cx, p.cy, rr, 1, nzOf(p), 0.012); stroke(ctx, k.main, 0.006 + 0.004 * (p.n - i) / p.n, 0.2 + 0.5 * (1 - i / p.n)); }
        C.blobPath(ctx, p.blob, { imperf: 1 - b, grow: 0.88 + 0.12 * b }); fill(ctx, k.main);
      } else {
        const g = 0.88 + 0.14 * b;
        [-1, 1].forEach((sd) => { petal(ctx, p.cx + sd * p.s * 0.06, p.cy - p.s * 0.55, p.s * 1.25 * g, p.s * 0.42 * g, Math.PI / 2 + sd * p.tilt, -sd * 0.12); fill(ctx, k.main); });
        ctx.beginPath(); ctx.moveTo(p.cx, p.cy - p.s * 0.95); ctx.lineTo(p.cx, p.cy - p.s * 0.45); stroke(ctx, k.line, 0.012);
      }
    },
  };

  // Tongues sway on slow, unrelated clocks (3–6 s), so the fire never
  // flickers; embers rise and fade in and out.
  P.fire = {
    label: 'fire', motion: 'tongues lean and lift slowly; embers rise and fade',
    build: (r, pl) => ({ ...pl, kind: r.pick(['tongues', 'tongues', 'embers']), tongues: Array.from({ length: r.int(3, 5) }, () => ({ x: r.range(-0.45, 0.45), h: r.range(0.9, 1.5), w: r.range(0.28, 0.4), ph: r.range(0, TAU), per: r.range(3.2, 5.8) })), embers: Array.from({ length: r.int(10, 18) }, () => ({ x: r.range(-0.6, 0.6), y: r.next(), v: r.range(0.06, 0.11), ph: r.range(0, TAU), z: r.range(0.006, 0.012) })), log: r.chance(0.6), coals: Array.from({ length: r.int(5, 8) }, (_, i, ) => ({ dx: r.range(-0.75, 0.75), dy: r.range(-0.12, 0.08), w: r.range(0.18, 0.32), h: r.range(0.09, 0.15), rot: r.range(-0.3, 0.3), ph: r.range(0, TAU), per: r.range(4, 8) })) }),
    draw(ctx, p, k, t, still) {
      const base = p.cy + p.s * 0.7;
      soft(ctx, p.cx, base - p.s * 0.2, p.s * 1.7, k.glow, 0.32 + (still ? 0 : 0.06 * S(t, 6.1)));
      if (p.kind === 'tongues') p.tongues.forEach((g) => {
        const h = p.s * g.h * (0.9 + (still ? 0 : 0.1 * S(t, g.per, g.ph))), sw = still ? 0 : 0.06 * p.s * S(t, g.per * 1.3, g.ph + 1), x = p.cx + g.x * p.s, w = g.w * p.s;
        [[k.main, 1], [k.alt, 0.62], [k.glow, 0.3]].forEach(([col, f]) => { ctx.beginPath(); ctx.moveTo(x - w * f, base); ctx.bezierCurveTo(x - w * f, base - h * f * 0.5, x + sw - w * f * 0.3, base - h * f * 0.85, x + sw * 1.4, base - h * f); ctx.bezierCurveTo(x + sw + w * f * 0.3, base - h * f * 0.85, x + w * f, base - h * f * 0.5, x + w * f, base); ctx.closePath(); fill(ctx, col, 0.85); });
      });
      else {
        // A bed of coals: each glows from within on its own slow clock.
        soft(ctx, p.cx, base - p.s * 0.1, p.s * 1.1, k.alt, 0.35 + (still ? 0 : 0.1 * S(t, 7.3)));
        p.coals.forEach((q) => { const x = p.cx + q.dx * p.s, y = base + q.dy * p.s, g = still ? 0.6 : 0.5 + 0.5 * S(t, q.per, q.ph); ctx.beginPath(); ctx.ellipse(x, y, q.w * p.s, q.h * p.s, q.rot, 0, TAU); fill(ctx, k.line); ctx.beginPath(); ctx.ellipse(x, y - q.h * p.s * 0.15, q.w * p.s * 0.7, q.h * p.s * 0.45, q.rot, 0, TAU); fill(ctx, k.alt, 0.35 + 0.5 * g); ctx.beginPath(); ctx.ellipse(x, y - q.h * p.s * 0.2, q.w * p.s * 0.35, q.h * p.s * 0.2, q.rot, 0, TAU); fill(ctx, k.glow, 0.3 + 0.6 * g); });
      }
      if (p.log && p.kind === 'tongues') { C.cutPoly(ctx, [[p.cx - p.s * 0.8, base - 0.012], [p.cx + p.s * 0.8, base - 0.018], [p.cx + p.s * 0.82, base + 0.02], [p.cx - p.s * 0.78, base + 0.024]], C.makeRng('log'), 0.003); fill(ctx, k.line); }
      for (const e of p.embers) { const u = still ? e.y : (e.y + t * e.v) % 1, x = p.cx + e.x * p.s * (1 + u * 0.4) + 0.015 * S(t, 5, e.ph), y = base - u * p.s * 2.6; C.circle(ctx, x, y, e.z * (1 - u * 0.5) * (p.kind === 'embers' ? 1.3 : 1)); fill(ctx, k.glow, fade(u) * 0.95); }
    },
  };

  // Ripples open and fade (each ring fades in from nothing and out to
  // nothing, so the loop is seamless); a target breathes; two sources
  // interfere, their rings drifting outwards and fading at the edges.
  P.rings = {
    label: 'rings', motion: 'ripples open and fade; targets breathe; sources interfere',
    build: (r, pl) => ({ ...pl, kind: r.pick(['ripple', 'target', 'interference']), n: r.int(4, 8), sq: r.chance(0.4) ? r.range(0.3, 0.5) : 1, nzSeed: r.next(), d: r.range(0.16, 0.3), ang: r.range(0, TAU), w: r.range(0.005, 0.009), per: r.range(10, 14) }),
    draw(ctx, p, k, t, still) {
      const R = p.s * 1.15, nz = nzOf(p);
      if (p.kind === 'ripple') {
        for (let i = 0; i < p.n; i++) { const u = still ? (i + 0.5) / p.n : (t / p.per + i / p.n) % 1; wobRing(ctx, p.cx, p.cy, 0.015 + R * u, p.sq, nz, 0.012); stroke(ctx, k.main, p.w * (1.4 - u), fade(u) * 0.9); }
        C.circle(ctx, p.cx, p.cy, 0.012); fill(ctx, k.main);
      } else if (p.kind === 'target') {
        const b = BR(t, still);
        for (let i = p.n; i >= 1; i--) { wobRing(ctx, p.cx, p.cy, R * i / p.n * (0.95 + 0.05 * BR(t - i * 0.3, still)), p.sq, nz, 0.01); if (i % 2) fill(ctx, i === 1 ? k.alt : k.main, i === 1 ? 1 : 0.16); stroke(ctx, k.main, p.w, 0.85); }
        void b;
      } else {
        const ox = Math.cos(p.ang) * p.d / 2, oy = Math.sin(p.ang) * p.d / 2, n = p.n * 2 + 4;
        [[p.cx - ox, p.cy - oy, k.main], [p.cx + ox, p.cy + oy, k.alt]].forEach(([x, y, cc], j) => { for (let i = 0; i < n; i++) { const u = still ? (i + 0.5) / n : ((i + t / p.per * (j ? 1.13 : 1)) / n) % 1; wobRing(ctx, x, y, 0.01 + R * u, p.sq, nz, 0.005); stroke(ctx, cc, p.w * 0.6, fade(u) * 0.8); } });
      }
    },
  };

  P.mandala = {
    label: 'mandala', motion: 'tiers turn slowly against each other and breathe',
    build: (r, pl) => { const n = r.pick([4, 5, 6, 8, 8, 10, 12]); return { ...pl, n, tiers: Array.from({ length: r.int(2, 3) }, (_, i) => ({ el: r.pick(['petal', 'petal', 'dot', 'arc', 'leaf']), rr: lerp(0.35, 1, (i + 1) / 3) * r.range(0.85, 1.05), sz: r.range(0.18, 0.32), off: r.chance(0.5) ? 0.5 : 0, dir: r.sign() })), core: r.range(0.08, 0.16), ring: r.chance(0.6) }; },
    draw(ctx, p, k, t, still) {
      const rot = still ? 0 : t / 240 * TAU, b = BR(t, still), S2 = p.s * (0.96 + 0.04 * b);
      if (p.ring) { C.circle(ctx, p.cx, p.cy, S2 * 1.08); stroke(ctx, k.line, 0.004, 0.5); }
      p.tiers.slice().reverse().forEach((T, ti) => {
        for (let i = 0; i < p.n; i++) {
          const a = (i + T.off) / p.n * TAU + rot * T.dir - Math.PI / 2, r0 = S2 * T.rr, col = ti % 2 ? k.alt : k.main;
          if (T.el === 'petal' || T.el === 'leaf') { petal(ctx, p.cx + Math.cos(a) * r0 * 0.35, p.cy + Math.sin(a) * r0 * 0.35, r0 * 0.65 * (0.95 + 0.05 * b), S2 * T.sz * (T.el === 'leaf' ? 0.25 : 0.4) * (6 / p.n + 0.4), a); fill(ctx, col, 0.92); }
          else if (T.el === 'dot') { C.circle(ctx, p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0, S2 * T.sz * 0.22); fill(ctx, col); }
          else { ctx.beginPath(); ctx.arc(p.cx + Math.cos(a) * r0 * 0.7, p.cy + Math.sin(a) * r0 * 0.7, r0 * 0.3, a - 1.2, a + 1.2); stroke(ctx, col, 0.007); }
        }
      });
      C.circle(ctx, p.cx, p.cy, S2 * p.core * (0.9 + 0.2 * b)); fill(ctx, k.alt);
    },
  };

  // Rain as a figure: streaks inside a soft window, each fading in at the top
  // and out at the bottom.
  P.streaks = {
    label: 'streaks', motion: 'falls, every drop fading in and out',
    build: (r, pl) => ({ ...pl, slant: r.range(-0.22, 0.04), drops: Array.from({ length: r.int(20, 32) }, () => ({ x: r.next(), y: r.next(), l: r.range(0.05, 0.11), v: r.range(0.07, 0.12), a: r.range(0.45, 1) })) }),
    draw(ctx, p, k, t, still) {
      const s2 = p.s * 1.15;
      for (const d of p.drops) { const u = still ? d.y : (d.y + t * d.v) % 1, y = p.cy - s2 + u * s2 * 2, x = p.cx - s2 + d.x * s2 * 2 + (u - 0.5) * s2 * 2 * p.slant; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d.l * p.slant, y + d.l); stroke(ctx, k.main, 0.008, d.a * fade(u)); }
    },
  };

  P.waves = {
    label: 'waves', motion: 'rows travel at their own speeds',
    build: (r, pl) => ({ ...pl, rows: r.int(5, 9), amp: r.range(0.01, 0.024), f: r.range(2, 4.5), dash: r.chance(0.35), v: r.range(0.08, 0.14) }),
    draw(ctx, p, k, t, still) {
      for (let i = 0; i < p.rows; i++) {
        const y = lerp(p.cy - p.s * 0.7, p.cy + p.s * 0.7, i / (p.rows - 1)), ph = (still ? 0 : TAU * t * p.v * (1 + i * 0.07)) + i * 0.9, half = p.s * (1 - Math.abs(i / (p.rows - 1) - 0.5) * 0.6);
        ctx.beginPath(); for (let x = p.cx - half; x <= p.cx + half; x += 0.012) { const y2 = y + p.amp * Math.sin(TAU * p.f * x + ph); x === p.cx - half ? ctx.moveTo(x, y2) : ctx.lineTo(x, y2); }
        if (p.dash) ctx.setLineDash([0.05, 0.03]);
        stroke(ctx, i % 2 ? k.line : k.main, 0.007, 0.9); ctx.setLineDash([]);
      }
    },
  };

  P.scales = {
    label: 'scales', motion: 'drifts slowly sideways and back',
    build: (r, pl) => ({ ...pl, R: r.range(0.05, 0.07), rings: r.int(3, 4) }),
    draw(ctx, p, k, t, still) {
      const img = cached(ctx, p, k, (g) => {
        const R = p.R;
        for (let row = 0, y = -0.1 - R; y < 1.1 + R * 2; row++, y += R * 0.5) for (let x = (row % 2) * R - R - 0.1; x < 1.1 + R; x += R * 2) {
          g.beginPath(); g.arc(x, y, R, Math.PI, TAU); g.lineTo(x + R, y + R); g.lineTo(x - R, y + R); g.closePath(); fill(g, k.paper);
          for (let i = 0; i < p.rings; i++) { g.beginPath(); g.arc(x, y, R * (1 - i / p.rings), Math.PI, TAU); stroke(g, i ? k.line : k.main, 0.005, 0.9); }
        }
      });
      ctx.save(); ctx.beginPath(); ctx.arc(p.cx, p.cy, p.s, 0, TAU); ctx.clip();
      ctx.drawImage(img, -0.1 + (still ? 0 : 0.04 * S(t, 20)), -0.1, 1.2, 1.2); ctx.restore();
    },
  };

  // Stars placed to imply a shape: the shape is never drawn, only suggested
  // by where the bright stars sit; faint companions fill the space around.
  const ASTERISMS = {
    dipper: [[-1, -0.25, 1], [-0.62, -0.3, 0.8], [-0.28, -0.12, 0.85], [0.02, 0, 0.7], [0.1, 0.38, 0.9], [0.62, 0.42, 1], [0.66, 0.02, 0.85]],
    cassiopeia: [[-1, -0.3, 0.9], [-0.5, 0.32, 1], [0, -0.06, 0.8], [0.5, 0.36, 1], [1, -0.22, 0.85]],
    cross: [[0, -1, 1], [0, 0.9, 1], [-0.62, -0.02, 0.85], [0.58, 0.12, 0.8], [0.28, 0.42, 0.55]],
    swan: [[0, -1, 1], [0, -0.32, 0.9], [0.02, 0.3, 0.75], [0.04, 0.95, 0.85], [-0.86, -0.18, 0.8], [-0.42, -0.28, 0.65], [0.46, -0.3, 0.65], [0.9, -0.12, 0.8]],
    lotus: Array.from({ length: 9 }, (_, i) => { const u = i / 8 - 0.5, a = -Math.PI / 2 + u * 2.2, rr = 0.9 - Math.abs(u) * 0.6; return [Math.cos(a) * rr, 0.55 + Math.sin(a) * rr, 1 - Math.abs(u)]; }),
    ring: Array.from({ length: 12 }, (_, i) => [Math.cos(i / 12 * TAU), Math.sin(i / 12 * TAU), i % 3 ? 0.6 : 1]),
  };
  P.stars = {
    label: 'star shape', motion: 'each star brightens and dims on its own slow clock',
    build: (r, pl, slot) => {
      const shape = r.pick(slot === 'accent' ? ['ring', 'cassiopeia', 'cross'] : Object.keys(ASTERISMS)), rot = r.range(-0.35, 0.35), sc = pl.s * r.range(0.85, 1.05);
      const main = ASTERISMS[shape].map(([x, y, b]) => { const c = Math.cos(rot), s = Math.sin(rot), jx = r.range(-0.05, 0.05), jy = r.range(-0.05, 0.05); return { x: pl.cx + ((x + jx) * c - (y + jy) * s) * sc, y: pl.cy + ((x + jx) * s + (y + jy) * c) * sc, z: (0.007 + 0.009 * b) * (slot === 'accent' ? 0.7 : 1), per: r.range(7, 13), ph: r.range(0, TAU), b }; });
      const faint = slot === 'accent' ? [] : Array.from({ length: r.int(10, 18) }, () => ({ x: pl.cx + r.range(-1.3, 1.3) * pl.s, y: pl.cy + r.range(-1.3, 1.3) * pl.s, z: r.range(0.0015, 0.003), per: r.range(6, 12), ph: r.range(0, TAU), b: 0.3 }));
      return { ...pl, shape, main, faint };
    },
    draw(ctx, p, k, t, still) {
      for (const q of p.faint) { C.circle(ctx, q.x, q.y, q.z); fill(ctx, k.line, still ? 0.5 : 0.35 + 0.3 * S(t, q.per, q.ph)); }
      for (const q of p.main) {
        const tw = still ? 0.8 : 0.72 + 0.28 * S(t, q.per, q.ph);
        soft(ctx, q.x, q.y, q.z * 4.5, k.glow, 0.35 * tw * q.b);
        C.circle(ctx, q.x, q.y, q.z * (0.85 + 0.15 * tw)); fill(ctx, k.main, 0.6 + 0.4 * tw);
        if (q.b > 0.85) { ctx.beginPath(); ctx.moveTo(q.x - q.z * 2.6 * tw, q.y); ctx.lineTo(q.x + q.z * 2.6 * tw, q.y); ctx.moveTo(q.x, q.y - q.z * 2.6 * tw); ctx.lineTo(q.x, q.y + q.z * 2.6 * tw); stroke(ctx, k.main, 0.0025, 0.6 * tw); }
      }
    },
  };

  P.lotus = {
    label: 'lotus', motion: 'opens on the inhale, closes on the exhale',
    build: (r, pl) => ({ ...pl, n: r.pick([5, 7, 9]), tiers: r.int(1, 2), spread: r.range(0.9, 1.35), water: r.chance(0.5) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), base = p.cy + p.s * 0.55;
      if (p.water) { ctx.beginPath(); ctx.ellipse(p.cx, base + 0.01, p.s * 1.2 * (0.97 + 0.03 * b), p.s * 0.14, 0, 0, TAU); fill(ctx, k.alt, 0.35); }
      for (let tr = p.tiers - 1; tr >= 0; tr--) {
        const n = p.n - tr * 2, sp = p.spread * (0.82 + 0.18 * b) * (1 + tr * 0.25);
        for (let i = 0; i < n; i++) { const u = n === 1 ? 0 : i / (n - 1) - 0.5, a = -Math.PI / 2 + u * sp; petal(ctx, p.cx, base, p.s * (1.15 - Math.abs(u) * 0.5) * (1 - tr * 0.18), p.s * 0.2, a); fill(ctx, tr ? k.alt : k.main, 0.92); stroke(ctx, k.paper, 0.004, 0.6); }
      }
    },
  };

  P.ammonite = {
    label: 'ammonite', motion: 'turns once every five minutes',
    build: (r, pl) => ({ ...pl, turns: r.range(2.2, 3.2), k: r.range(0.16, 0.22), septa: r.int(14, 24), dir: r.sign() }),
    draw(ctx, p, k, t, still) {
      const rot = (still ? 0 : t / 300 * TAU) * p.dir, th1 = p.turns * TAU, R = (th) => p.s * Math.exp(p.k * (th - th1));
      C.circle(ctx, p.cx, p.cy, p.s); fill(ctx, k.main, 0.85);
      ctx.beginPath(); for (let i = 0; i <= 300; i++) { const th = th1 * i / 300, rr = R(th), a = p.dir * th + rot; i ? ctx.lineTo(p.cx + rr * Math.cos(a), p.cy + rr * Math.sin(a)) : ctx.moveTo(p.cx + rr * Math.cos(a), p.cy + rr * Math.sin(a)); } stroke(ctx, k.line, 0.007);
      for (let i = 1; i <= p.septa; i++) { const th = th1 * (0.25 + 0.75 * i / p.septa), a = p.dir * th + rot, r0 = R(th - TAU), r1 = R(th); ctx.beginPath(); ctx.moveTo(p.cx + r0 * Math.cos(a), p.cy + r0 * Math.sin(a)); ctx.quadraticCurveTo(p.cx + (r0 + r1) / 2 * Math.cos(a + 0.12 * p.dir), p.cy + (r0 + r1) / 2 * Math.sin(a + 0.12 * p.dir), p.cx + r1 * Math.cos(a), p.cy + r1 * Math.sin(a)); stroke(ctx, k.line, 0.004, 0.7); }
    },
  };

  P.cairn = {
    label: 'cairn', motion: 'the stones settle on the breath, the top one last',
    build: (r, pl) => { const n = r.int(3, 5); let y = pl.cy + pl.s * 0.9; const st = []; for (let i = 0; i < n; i++) { const rx = pl.s * (0.75 - i * 0.12) * r.range(0.85, 1.1), ry = rx * r.range(0.42, 0.58); y -= ry; const b = C.makeBlob(r, pl.cx + r.range(-0.12, 0.12) * pl.s, y, 1, 0.8, 0.006); b.rot = r.range(-0.12, 0.12); b.rx = rx; b.ry = ry; st.push(b); y -= ry * 0.88; } return { ...pl, st }; },
    draw(ctx, p, k, t, still) { p.st.forEach((s, i) => { const b = BR(t - i * 0.5, still); C.blobPath(ctx, s, { sx: s.rx, sy: s.ry, dy: -0.004 * b * i / p.st.length }); fill(ctx, i % 2 ? k.alt : k.main); }); },
  };

  P.threads = {
    label: 'threads', motion: 'flow sideways like air through a field',
    build: (r, pl) => ({ ...pl, lines: Array.from({ length: r.int(6, 10) }, () => ({ y: r.next(), amp: r.range(0.02, 0.06), f: r.range(0.6, 1.4), ph: r.range(0, TAU), per: r.range(9, 16) })) }),
    draw(ctx, p, k, t, still) {
      p.lines.forEach((L, i) => {
        const y0 = p.cy - p.s * 0.6 + L.y * p.s * 1.2, ph = L.ph + (still ? 0 : TAU * t / L.per);
        ctx.beginPath(); for (let x = p.cx - p.s * 1.25, j = 0; x <= p.cx + p.s * 1.25; x += 0.015, j++) { const y = y0 + L.amp * Math.sin(TAU * L.f * x + ph) + 0.018 * Math.sin(TAU * 0.4 * x + ph * 0.5); j ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
        stroke(ctx, i % 3 ? k.line : k.main, 0.01 - (i % 3) * 0.002, 0.95);
      });
    },
  };

  // Tall grass bending together in a slow wind.
  P.grass = {
    label: 'grass', motion: 'bends in a slow wind, gusts travelling across',
    build: (r, pl) => ({ ...pl, blades: Array.from({ length: r.int(26, 40) }, () => ({ x: r.range(-1.1, 1.1), h: r.range(0.6, 1.3), w: r.range(0.004, 0.008), ph: r.range(0, 0.6), seed: r.chance(0.25) })), lean: r.range(0.05, 0.18) }),
    draw(ctx, p, k, t, still) {
      const base = p.cy + p.s * 0.75;
      p.blades.forEach((B, i) => {
        const x = p.cx + B.x * p.s, gust = still ? 0.5 : 0.5 + 0.5 * S(t, 9, -B.x * 1.6 + B.ph), bend = p.s * (p.lean + 0.18 * gust) * B.h, h = p.s * 1.4 * B.h;
        ctx.beginPath(); ctx.moveTo(x, base); ctx.quadraticCurveTo(x, base - h * 0.6, x + bend, base - h); stroke(ctx, i % 3 ? k.main : k.line, B.w, 0.9);
        if (B.seed) { petal(ctx, x + bend, base - h, p.s * 0.12, p.s * 0.03, -Math.PI / 2 + bend / h * 1.5); fill(ctx, k.alt); }
      });
    },
  };

  // A few birds gliding on a slow closed path, wings beating slowly.
  P.flock = {
    label: 'flock', motion: 'glides on a slow loop, wings rising and falling',
    build: (r, pl, slot) => {
      const kind = slot === 'accent' ? 'pair' : r.pick(['skein', 'scatter', 'pair']), n = kind === 'skein' ? r.int(5, 7) : kind === 'pair' ? 2 : r.int(4, 7);
      const birds = Array.from({ length: n }, (_, i) => kind === 'skein' ? { dx: (i - (n - 1) / 2) * 0.32, dy: Math.abs(i - (n - 1) / 2) * 0.22, s: 1 } : { dx: r.range(-1, 1), dy: r.range(-0.6, 0.6), s: r.range(0.7, 1.1) });
      return { ...pl, kind, birds: birds.map((b) => ({ ...b, ph: r.range(0, TAU), per: r.range(1.8, 2.6) })), loop: r.range(18, 26) };
    },
    draw(ctx, p, k, t, still) {
      const ox = still ? 0 : p.s * 0.18 * S(t, p.loop), oy = still ? 0 : p.s * 0.08 * S(t, p.loop / 2, 1), sz = p.s * (p.kind === 'skein' ? 0.22 : 0.3);
      p.birds.forEach((b) => {
        const x = p.cx + b.dx * p.s + ox, y = p.cy + b.dy * p.s + oy, f = still ? 0.5 : 0.5 + 0.5 * S(t, b.per, b.ph), w = sz * b.s;
        ctx.beginPath(); ctx.moveTo(x - w, y - w * (0.15 + 0.45 * f)); ctx.quadraticCurveTo(x - w * 0.45, y - w * 0.35, x, y); ctx.quadraticCurveTo(x + w * 0.45, y - w * 0.35, x + w, y - w * (0.15 + 0.45 * f));
        stroke(ctx, k.main, Math.max(0.004, w * 0.14), 0.95);
      });
    },
  };

  // Petals drifting down, turning as they fall.
  P.petals = {
    label: 'petals', motion: 'drift down and turn, fading in and out',
    build: (r, pl) => ({ ...pl, ps: Array.from({ length: r.int(7, 12) }, () => ({ x: r.range(-1, 1), y: r.next(), v: r.range(0.03, 0.055), ph: r.range(0, TAU), z: r.range(0.6, 1.1), spin: r.range(0.2, 0.6) })) }),
    draw(ctx, p, k, t, still) {
      p.ps.forEach((q, i) => {
        const u = still ? q.y : (q.y + t * q.v) % 1, x = p.cx + q.x * p.s + p.s * 0.2 * S(t, 7, q.ph), y = p.cy - p.s * 1.1 + u * p.s * 2.2, a = q.ph + (still ? 0 : TAU * t * q.spin / 10);
        petal(ctx, x, y, p.s * 0.3 * q.z, p.s * 0.1 * q.z, a); fill(ctx, i % 3 ? k.main : k.alt, fade(u));
      });
    },
  };

  P.moon = {
    label: 'moon', motion: 'its glow breathes; the phase creeps',
    build: (r, pl) => ({ ...pl, ph: r.range(0.08, 0.42) }),
    draw(ctx, p, k, t, still) {
      const R = p.s * 0.7, ph = p.ph + (still ? 0 : 0.03 * S(t, 120)), c = Math.cos(ph * TAU);
      soft(ctx, p.cx, p.cy, R * 2.4, k.glow, 0.22 + (still ? 0 : 0.06 * S(t, 10)));
      C.circle(ctx, p.cx, p.cy, R); fill(ctx, k.main, 0.2);
      ctx.save(); C.circle(ctx, p.cx, p.cy, R); ctx.clip();
      ctx.beginPath(); ctx.arc(p.cx, p.cy, R, -Math.PI / 2, Math.PI / 2, false); ctx.ellipse(p.cx, p.cy, Math.abs(c) * R, R, 0, Math.PI / 2, -Math.PI / 2, c > 0); fill(ctx, k.main); ctx.restore();
    },
  };

  // One round body: sun, lamp, moon or bindu. Breathes between true circle
  // and pebble; the rayed kind turns its rays slowly.
  P.disc = {
    label: 'disc', motion: 'breathes between round and pebble; rays turn slowly',
    build: (r, pl, slot) => ({ ...pl, kind: slot === 'accent' ? 'plain' : r.pick(['plain', 'plain', 'rayed', 'halo']), n: r.pick([12, 16, 24]), blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.6, 0.7, 0.003) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.6;
      if (p.kind === 'halo') soft(ctx, p.cx, p.cy, R * 2.6, k.glow, 0.3 + 0.1 * b);
      if (p.kind === 'rayed') { const rot = still ? 0 : t / 200 * TAU; for (let i = 0; i < p.n; i++) { const a = i / p.n * TAU + rot, r0 = R * 1.3, r1 = R * (1.7 + (i % 2 ? 0.25 : 0.5)) * (0.96 + 0.04 * b); ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0); ctx.lineTo(p.cx + Math.cos(a) * r1, p.cy + Math.sin(a) * r1); stroke(ctx, k.alt, 0.007); } }
      C.blobPath(ctx, p.blob, { imperf: 1 - b, grow: 0.95 + 0.05 * b }); fill(ctx, k.main);
    },
  };

  return P;
})();
