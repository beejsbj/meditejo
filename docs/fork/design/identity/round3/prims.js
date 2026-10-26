/* Round 3 primitives: small seeded generators that each fit a card.
 *
 * Every primitive is { label, motion, ground?, build(r, place, slot), draw(ctx, p, k, t, still) }.
 *   place: { cx, cy, s } in unit card space (s is a radius-like size);
 *          a ground fills the card and ignores it.
 *   slot:  'ground' | 'figure' | 'accent', so a primitive can be quieter as a
 *          ground or simpler as an accent.
 *   k:     the inks the composition assigned: { paper, main, alt, line, glow }.
 *   t:     seconds; still freezes motion at a calm frame.
 * Everything is drawn with slightly wobbly, hand-cut geometry. */
const Prims = (() => {
  'use strict';
  const C = Core, { TAU, lerp, clamp, css, mix } = C;
  const BR = (t, still, ph = 0) => (still ? 0.5 : 0.5 - 0.5 * Math.cos(TAU * t / C.BREATH + ph)); // 0..1 breath

  // ---------- hand-made helpers ----------
  // A circle whose radius wanders a little, like a ring drawn with a pen.
  function wobRing(ctx, cx, cy, r, ry, nz, amt, a0 = 0, a1 = TAU, keep) {
    if (!keep) ctx.beginPath();
    const M = Math.max(24, Math.ceil(r * 260));
    for (let i = 0; i <= M; i++) {
      const a = lerp(a0, a1, i / M), rr = r * (1 + amt * nz(a * 1.3 + r * 9));
      const x = cx + rr * Math.cos(a), y = cy + rr * (ry ?? 1) * Math.sin(a);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
  }
  function wobLine(ctx, pts, nz, amt) {
    ctx.beginPath();
    pts.forEach(([x, y], i) => { const d = amt * nz(i * 0.37 + x * 3); i ? ctx.lineTo(x, y + d) : ctx.moveTo(x, y + d); });
  }
  const fill = (ctx, col, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = css(col); ctx.fill(); ctx.globalAlpha = 1; };
  const stroke = (ctx, col, w, a = 1) => { ctx.globalAlpha = a; ctx.strokeStyle = css(col); ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); ctx.globalAlpha = 1; };
  const soft = (ctx, x, y, r, col, a) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  // Paint a primitive's static part once per size and inks, into a raster
  // covering the card plus a 0.1 margin, so it can be moved cheaply.
  function cached(ctx, p, k, paint) {
    const px = Math.round(ctx.getTransform().a), key = `${px}|${C.hex(k.paper)}|${C.hex(k.main)}|${C.hex(k.line)}`;
    if (!p._cache || p._cache.key !== key) {
      const cv = document.createElement('canvas'); cv.width = cv.height = Math.round(px * 1.2);
      const g = cv.getContext('2d'); g.setTransform(px, 0, 0, px, 0.1 * px, 0.1 * px); paint(g);
      Object.defineProperty(p, '_cache', { value: { key, cv }, writable: true, enumerable: false });
    }
    return p._cache.cv;
  }
  function petal(ctx, x, y, len, wid, ang, bend = 0) {
    const c = Math.cos(ang), s = Math.sin(ang), P = (u, v) => [x + u * c - v * s, y + u * s + v * c];
    const [ax, ay] = P(len, bend * len), [l1x, l1y] = P(len * 0.35, wid), [l2x, l2y] = P(len * 0.8, wid * 0.6 + bend * len * 0.5), [r1x, r1y] = P(len * 0.35, -wid), [r2x, r2y] = P(len * 0.8, -wid * 0.6 + bend * len * 0.5);
    ctx.beginPath(); ctx.moveTo(x, y); ctx.bezierCurveTo(l1x, l1y, l2x, l2y, ax, ay); ctx.bezierCurveTo(r2x, r2y, r1x, r1y, x, y); ctx.closePath();
  }

  const P = {};

  // 1. Breath: an orb whose halo rings follow the breath with a lag, or a
  // pair of lobes that fill and empty.
  P.breath = {
    label: 'breath', motion: 'swells and settles every 10 s',
    build: (r, pl) => ({ ...pl, kind: r.pick(['orb', 'orb', 'lungs']), n: r.int(3, 5), nz: C.noise1(r, 2), blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.55, 0.7, 0.003), tilt: r.range(0.3, 0.55) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      if (p.kind === 'orb') {
        for (let i = p.n - 1; i >= 0; i--) { const bi = BR(t - i * 0.6, still), rr = p.s * (0.45 + 0.55 * (i + 1) / p.n) * (0.88 + 0.12 * bi); wobRing(ctx, p.cx, p.cy, rr, 1, p.nz, 0.012); i === 0 ? fill(ctx, k.main) : stroke(ctx, k.main, 0.006 + 0.004 * (p.n - i) / p.n, 0.25 + 0.5 * (1 - i / p.n)); }
        C.blobPath(ctx, p.blob, { imperf: 1 - b, grow: 0.9 + 0.1 * b }); fill(ctx, k.main);
      } else {
        const g = 0.9 + 0.12 * b;
        [-1, 1].forEach((sd) => { petal(ctx, p.cx + sd * p.s * 0.06, p.cy - p.s * 0.55, p.s * 1.25 * g, p.s * 0.42 * g, Math.PI / 2 + sd * p.tilt, -sd * 0.12); fill(ctx, k.main); });
        ctx.beginPath(); ctx.moveTo(p.cx, p.cy - p.s * 0.95); ctx.lineTo(p.cx, p.cy - p.s * 0.45); stroke(ctx, k.line, 0.012);
      }
    },
  };

  // 2. Fire: layered tongues that sway on their own clocks, embers rising.
  P.fire = {
    label: 'fire', motion: 'tongues flicker, embers rise',
    build: (r, pl) => ({ ...pl, tongues: Array.from({ length: r.int(3, 5) }, () => ({ x: r.range(-0.45, 0.45), h: r.range(0.9, 1.6), w: r.range(0.28, 0.4), ph: r.range(0, TAU) })), embers: Array.from({ length: r.int(8, 16) }, () => ({ x: r.range(-0.6, 0.6), y: r.next(), v: r.range(0.08, 0.16), ph: r.range(0, TAU), z: r.range(0.006, 0.012) })), log: r.chance(0.6) }),
    draw(ctx, p, k, t, still) {
      const base = p.cy + p.s * 0.7, fl = (i) => (still ? 0.5 : 0.5 + 0.5 * Math.sin(t * 2.1 + i * 1.7) * Math.sin(t * 1.3 + i));
      soft(ctx, p.cx, base - p.s * 0.2, p.s * 1.6, k.glow, 0.35);
      p.tongues.forEach((g, i) => {
        const h = p.s * g.h * (0.85 + 0.25 * fl(i)), sw = still ? 0 : 0.08 * p.s * Math.sin(t * 1.6 + g.ph), x = p.cx + g.x * p.s, w = g.w * p.s;
        [[k.main, 1], [k.alt, 0.62], [k.glow, 0.3]].forEach(([col, f]) => { ctx.beginPath(); ctx.moveTo(x - w * f, base); ctx.bezierCurveTo(x - w * f, base - h * f * 0.5, x + sw - w * f * 0.3, base - h * f * 0.85, x + sw * 1.4, base - h * f); ctx.bezierCurveTo(x + sw + w * f * 0.3, base - h * f * 0.85, x + w * f, base - h * f * 0.5, x + w * f, base); ctx.closePath(); fill(ctx, col, 0.85); });
      });
      if (p.log) { C.cutPoly(ctx, [[p.cx - p.s * 0.8, base - 0.012], [p.cx + p.s * 0.8, base - 0.018], [p.cx + p.s * 0.82, base + 0.02], [p.cx - p.s * 0.78, base + 0.024]], C.makeRng('log' + p.cx), 0.003); fill(ctx, k.line); }
      for (const e of p.embers) { const u = still ? e.y : (e.y + t * e.v) % 1, x = p.cx + e.x * p.s + 0.02 * Math.sin(t + e.ph), y = base - u * p.s * 2.4; C.circle(ctx, x, y, e.z * (1 - u * 0.6)); fill(ctx, k.glow, 1 - u); }
    },
  };

  // 3. Rings: ripples spreading, a still target, or two sources interfering.
  P.rings = {
    label: 'rings', ground: true, motion: 'ripples open outwards',
    build: (r, pl, slot) => ({ ...pl, kind: slot === 'ground' ? r.pick(['interference', 'target', 'ripple']) : r.pick(['ripple', 'target', 'target', 'interference']), n: r.int(4, 9), sq: r.chance(0.4) ? r.range(0.3, 0.5) : 1, nz: C.noise1(r, 2), d: r.range(0.18, 0.32), ang: r.range(0, TAU), w: r.range(0.004, 0.009), per: r.range(9, 13), slot }),
    draw(ctx, p, k, t, still) {
      const g = p.slot === 'ground', R = g ? 0.75 : p.s * 1.1, col = g ? k.line : k.main;
      if (p.kind === 'ripple') {
        for (let i = 0; i < p.n; i++) { const u = still ? (i + 0.5) / p.n : (t / p.per + i / p.n) % 1; wobRing(ctx, p.cx, p.cy, 0.02 + R * u, p.sq, p.nz, 0.015); stroke(ctx, col, p.w * (1.4 - u), Math.pow(1 - u, 1.2)); }
        C.circle(ctx, p.cx, p.cy, 0.012); fill(ctx, col);
      } else if (p.kind === 'target') {
        const b = BR(t, still);
        for (let i = p.n; i >= 1; i--) { wobRing(ctx, p.cx, p.cy, R * i / p.n * (0.97 + 0.03 * b), p.sq, p.nz, 0.01); if (i % 2 && !g) fill(ctx, i === 1 ? k.alt : col, i === 1 ? 1 : 0.18); stroke(ctx, col, p.w, 0.85); }
      } else {
        const ox = Math.cos(p.ang) * p.d / 2, oy = Math.sin(p.ang) * p.d / 2, n = p.n * 2 + 6;
        [[p.cx - ox, p.cy - oy, col], [p.cx + ox, p.cy + oy, g ? k.line : k.alt]].forEach(([x, y, cc], j) => { for (let i = 1; i <= n; i++) { const ph = still ? 0 : ((t / p.per) % 1) * (R / n) * (j ? -1 : 1); wobRing(ctx, x, y, R * i / n + ph, p.sq, p.nz, 0.006); stroke(ctx, cc, p.w * 0.6, 0.7); } });
      }
    },
  };

  // 4. Mandala: 4- to 12-fold, two or three sparse tiers, turning slowly.
  P.mandala = {
    label: 'mandala', motion: 'tiers turn slowly against each other',
    build: (r, pl) => { const n = r.pick([4, 5, 6, 8, 8, 10, 12]); return { ...pl, n, tiers: Array.from({ length: r.int(2, 3) }, (_, i) => ({ el: r.pick(['petal', 'petal', 'dot', 'arc', 'spoke', 'leaf']), rr: lerp(0.35, 1, (i + 1) / 3) * r.range(0.85, 1.05), sz: r.range(0.18, 0.32), off: r.chance(0.5) ? 0.5 : 0, dir: r.sign() })), core: r.range(0.08, 0.16), ring: r.chance(0.6) }; },
    draw(ctx, p, k, t, still) {
      const rot = still ? 0 : t / 240 * TAU, b = BR(t, still), S = p.s * (0.97 + 0.03 * b);
      if (p.ring) { C.circle(ctx, p.cx, p.cy, S * 1.08); stroke(ctx, k.line, 0.004, 0.5); }
      p.tiers.slice().reverse().forEach((T, ti) => {
        for (let i = 0; i < p.n; i++) {
          const a = (i + T.off) / p.n * TAU + rot * T.dir - Math.PI / 2, r0 = S * T.rr, col = ti % 2 ? k.alt : k.main;
          if (T.el === 'petal' || T.el === 'leaf') { petal(ctx, p.cx + Math.cos(a) * r0 * 0.35, p.cy + Math.sin(a) * r0 * 0.35, r0 * 0.65, S * T.sz * (T.el === 'leaf' ? 0.25 : 0.4) * (6 / p.n + 0.4), a); fill(ctx, col, 0.92); }
          else if (T.el === 'dot') { C.circle(ctx, p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0, S * T.sz * 0.22); fill(ctx, col); }
          else if (T.el === 'arc') { ctx.beginPath(); ctx.arc(p.cx + Math.cos(a) * r0 * 0.7, p.cy + Math.sin(a) * r0 * 0.7, r0 * 0.3, a - 1.2, a + 1.2); stroke(ctx, col, 0.007); }
          else { ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * r0 * 0.3, p.cy + Math.sin(a) * r0 * 0.3); ctx.lineTo(p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0); stroke(ctx, col, 0.006); }
        }
      });
      C.circle(ctx, p.cx, p.cy, S * p.core * (0.9 + 0.2 * b)); fill(ctx, k.alt);
    },
  };

  // 5. Strata: wavering bands like sediment or layered mist.
  P.strata = {
    label: 'strata', ground: true, motion: 'bands drift a little',
    build: (r, pl, slot) => ({ ...pl, n: r.int(5, 10), amp: r.range(0.006, 0.025), f: r.range(0.6, 2), ph: r.range(0, TAU), nz: C.noise1(r, 3), y0: slot === 'ground' ? 0 : pl.cy - pl.s, y1: slot === 'ground' ? 1 : pl.cy + pl.s, slot, tone: r.range(0.15, 0.45) }),
    draw(ctx, p, k, t, still) {
      const dr = still ? 0 : 0.02 * Math.sin(t / 20);
      for (let i = 0; i < p.n; i++) {
        const y = lerp(p.y0, p.y1, (i + 1) / (p.n + 1)), pts = [];
        for (let x = -0.05; x <= 1.05; x += 0.025) pts.push([x, y + p.amp * Math.sin(TAU * p.f * (x + dr * (i % 2 ? 1 : -1)) + p.ph + i * 0.7)]);
        if (p.slot === 'ground') { ctx.beginPath(); pts.forEach(([x, yy], j) => (j ? ctx.lineTo(x, yy) : ctx.moveTo(x, yy))); ctx.lineTo(1.05, 1.05); ctx.lineTo(-0.05, 1.05); ctx.closePath(); fill(ctx, i % 2 ? k.main : k.alt, p.tone * 0.5); }
        else { wobLine(ctx, pts, p.nz, 0.003); stroke(ctx, i % 3 ? k.line : k.main, 0.008, 0.85); }
      }
    },
  };

  // 6. Horizon: a split of sky and ground, a low disc, reflection marks.
  P.horizon = {
    label: 'horizon', ground: true, motion: 'reflections shimmer',
    build: (r, pl) => ({ ...pl, y: r.range(0.52, 0.68), sun: r.chance(0.7), sx: r.range(0.3, 0.7), sr: r.range(0.08, 0.14), bars: r.int(3, 6), blob: null }),
    draw(ctx, p, k, t, still) {
      ctx.fillStyle = css(k.main, 0.35); ctx.fillRect(0, p.y, 1, 1);
      ctx.beginPath(); ctx.moveTo(0, p.y); ctx.lineTo(1, p.y); stroke(ctx, k.line, 0.006);
      if (p.sun) { ctx.save(); ctx.beginPath(); ctx.rect(0, 0, 1, p.y); ctx.clip(); C.circle(ctx, p.sx, p.y - p.sr * 0.35, p.sr); fill(ctx, k.alt); ctx.restore(); }
      for (let i = 0; i < p.bars; i++) { const y = p.y + 0.03 + i * 0.035, w = p.sr * 2 * (0.9 - i * 0.14) * (still ? 1 : 1 + 0.15 * Math.sin(t * 0.9 + i)); ctx.beginPath(); ctx.moveTo(p.sx - w / 2, y); ctx.lineTo(p.sx + w / 2, y); stroke(ctx, k.alt, 0.012 - i * 0.0015, 0.8 - i * 0.1); }
    },
  };

  // 7. Streaks: slanted rain, falling.
  P.streaks = {
    label: 'streaks', ground: true, motion: 'falls',
    build: (r, pl, slot) => ({ ...pl, slant: r.range(-0.25, 0.05), n: slot === 'ground' ? r.int(50, 90) : r.int(18, 30), drops: Array.from({ length: 90 }, () => ({ x: r.range(-0.2, 1.2), y: r.next(), l: r.range(0.04, 0.1), v: r.range(0.08, 0.14), a: r.range(0.3, 0.9) })), slot }),
    draw(ctx, p, k, t, still) {
      const box = p.slot === 'ground' ? [0, 0, 1, 1] : [p.cx - p.s, p.cy - p.s, p.s * 2, p.s * 2];
      ctx.save(); ctx.beginPath(); p.slot === 'ground' ? ctx.rect(...box) : ctx.arc(p.cx, p.cy, p.s, 0, TAU); ctx.clip();
      for (const d of p.drops.slice(0, p.n)) { const y = box[1] + (((d.y + (still ? 0 : t * d.v)) % 1.15) - 0.1) * box[3], x = box[0] + d.x * box[2] + (y - box[1]) * p.slant; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d.l * p.slant, y + d.l); stroke(ctx, p.slot === 'ground' ? k.line : k.main, p.slot === 'ground' ? 0.0045 : 0.006, d.a * (p.slot === 'ground' ? 0.75 : 1)); }
      ctx.restore();
    },
  };

  // 8. Waves: a field of rows of sine strokes, travelling.
  P.waves = {
    label: 'waves', ground: true, motion: 'rows travel',
    build: (r, pl, slot) => ({ ...pl, rows: r.int(5, 11), amp: r.range(0.008, 0.022), f: r.range(2, 5), dash: r.chance(0.4), nz: C.noise1(r, 2), slot, v: r.range(0.15, 0.3) }),
    draw(ctx, p, k, t, still) {
      const [y0, y1] = p.slot === 'ground' ? [0.08, 0.95] : [p.cy - p.s * 0.7, p.cy + p.s * 0.7], [x0, x1] = p.slot === 'ground' ? [-0.05, 1.05] : [p.cx - p.s, p.cx + p.s];
      for (let i = 0; i < p.rows; i++) {
        const y = lerp(y0, y1, i / (p.rows - 1)), ph = (still ? 0 : t * p.v) + i * 0.9, pts = [];
        for (let x = x0; x <= x1; x += 0.012) pts.push([x, y + p.amp * Math.sin(TAU * p.f * x + ph)]);
        if (p.dash) ctx.setLineDash([0.05, 0.03]);
        wobLine(ctx, pts, p.nz, 0.0015); stroke(ctx, i % 2 ? k.line : k.main, 0.006, p.slot === 'ground' ? 0.4 : 0.9);
        ctx.setLineDash([]);
      }
    },
  };

  // 9. Scales (seigaiha): overlapping fans of concentric arcs.
  P.scales = {
    label: 'scales', ground: true, motion: 'drifts slowly sideways',
    build: (r, pl, slot) => ({ ...pl, R: slot === 'ground' ? r.range(0.07, 0.11) : r.range(0.05, 0.07), rings: r.int(3, 4), slot }),
    // Hundreds of overlapping fans: painted once into a raster with a margin,
    // then only moved.
    draw(ctx, p, k, t, still) {
      const img = cached(ctx, p, k, (g) => {
        const R = p.R;
        for (let row = 0, y = -0.1 - R; y < 1.1 + R * 2; row++, y += R * 0.5) {
          for (let x = (row % 2) * R - R - 0.1; x < 1.1 + R; x += R * 2) {
            g.beginPath(); g.arc(x, y, R, Math.PI, TAU); g.lineTo(x + R, y + R); g.lineTo(x - R, y + R); g.closePath(); fill(g, k.paper);
            for (let i = 0; i < p.rings; i++) { g.beginPath(); g.arc(x, y, R * (1 - i / p.rings), Math.PI, TAU); stroke(g, i ? k.line : k.main, 0.005, p.slot === 'ground' ? 0.45 : 0.9); }
          }
        }
      });
      const dx = still ? 0 : 0.04 * Math.sin(t / 18);
      ctx.save();
      if (p.slot !== 'ground') { ctx.beginPath(); ctx.arc(p.cx, p.cy, p.s, 0, TAU); ctx.clip(); }
      ctx.drawImage(img, -0.1 + dx, -0.1, 1.2, 1.2);
      ctx.restore();
    },
  };

  // 10. Points: a constellation, a few stars joined, the rest twinkling.
  P.points = {
    label: 'constellation', ground: true, motion: 'twinkles',
    build: (r, pl, slot) => { const n = slot === 'ground' ? r.int(40, 70) : r.int(6, 9); const pts = Array.from({ length: n }, () => ({ x: slot === 'ground' ? r.next() : pl.cx + r.range(-1, 1) * pl.s, y: slot === 'ground' ? r.next() * 0.7 : pl.cy + r.range(-0.8, 0.8) * pl.s, z: r.range(0.002, 0.007), ph: r.range(0, TAU), sp: r.range(0.4, 1.4) })); const chain = slot === 'ground' ? [] : pts.map((_, i) => i).sort((a, b) => pts[a].x - pts[b].x); return { ...pl, pts, chain, slot }; },
    draw(ctx, p, k, t, still) {
      if (p.chain.length) { ctx.beginPath(); p.chain.forEach((i, j) => (j ? ctx.lineTo(p.pts[i].x, p.pts[i].y) : ctx.moveTo(p.pts[i].x, p.pts[i].y))); stroke(ctx, k.line, 0.005, 0.7); }
      for (const q of p.pts) { const tw = still ? 0.8 : 0.5 + 0.5 * Math.sin(t * q.sp + q.ph); C.circle(ctx, q.x, q.y, q.z * (p.chain.length ? 2.6 : 1)); fill(ctx, p.chain.length ? k.main : k.line, 0.35 + 0.65 * tw); }
    },
  };

  // 11. Lotus: petals fanned from a base, opening on the inhale.
  P.lotus = {
    label: 'lotus', motion: 'opens on the inhale',
    build: (r, pl) => ({ ...pl, n: r.pick([5, 7, 9]), tiers: r.int(1, 2), spread: r.range(0.9, 1.4), water: r.chance(0.5) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), base = p.cy + p.s * 0.55;
      if (p.water) { ctx.beginPath(); ctx.ellipse(p.cx, base + 0.01, p.s * 1.2, p.s * 0.14, 0, 0, TAU); fill(ctx, k.alt, 0.35); }
      for (let tr = p.tiers - 1; tr >= 0; tr--) {
        const n = p.n - tr * 2, sp = p.spread * (0.85 + 0.15 * b) * (1 + tr * 0.25);
        for (let i = 0; i < n; i++) { const u = n === 1 ? 0 : i / (n - 1) - 0.5, a = -Math.PI / 2 + u * sp; petal(ctx, p.cx, base, p.s * (1.15 - Math.abs(u) * 0.5) * (1 - tr * 0.18), p.s * 0.2, a); fill(ctx, tr ? k.alt : k.main, 0.92); stroke(ctx, k.paper, 0.004, 0.6); }
      }
    },
  };

  // 12. Spiral: an ammonite, chambers and all, turning slowly.
  P.spiral = {
    label: 'ammonite', motion: 'turns very slowly',
    build: (r, pl) => ({ ...pl, turns: r.range(2.2, 3.2), k: r.range(0.16, 0.22), septa: r.int(14, 24), dir: r.sign(), nz: C.noise1(r, 2) }),
    draw(ctx, p, k, t, still) {
      const rot = (still ? 0 : t / 300 * TAU) * p.dir, th1 = p.turns * TAU, R = (th) => p.s * Math.exp(p.k * (th - th1));
      C.circle(ctx, p.cx, p.cy, p.s); fill(ctx, k.main, 0.85);
      ctx.beginPath(); for (let i = 0; i <= 300; i++) { const th = th1 * i / 300, rr = R(th); const a = p.dir * th + rot; i ? ctx.lineTo(p.cx + rr * Math.cos(a), p.cy + rr * Math.sin(a)) : ctx.moveTo(p.cx + rr * Math.cos(a), p.cy + rr * Math.sin(a)); } stroke(ctx, k.line, 0.007);
      for (let i = 1; i <= p.septa; i++) { const th = th1 * (0.25 + 0.75 * i / p.septa), a = p.dir * th + rot, r0 = R(th - TAU), r1 = R(th); ctx.beginPath(); ctx.moveTo(p.cx + r0 * Math.cos(a), p.cy + r0 * Math.sin(a)); ctx.quadraticCurveTo(p.cx + (r0 + r1) / 2 * Math.cos(a + 0.12 * p.dir), p.cy + (r0 + r1) / 2 * Math.sin(a + 0.12 * p.dir), p.cx + r1 * Math.cos(a), p.cy + r1 * Math.sin(a)); stroke(ctx, k.line, 0.004, 0.7); }
    },
  };

  // 13. Cairn: three to five stacked stones, cut by hand.
  P.cairn = {
    label: 'cairn', motion: 'the top stone settles',
    build: (r, pl) => { const n = r.int(3, 5); let y = pl.cy + pl.s * 0.9; const st = []; for (let i = 0; i < n; i++) { const rx = pl.s * (0.75 - i * 0.12) * r.range(0.85, 1.1), ry = rx * r.range(0.42, 0.58); y -= ry; const b = C.makeBlob(r, pl.cx + r.range(-0.04, 0.04) * pl.s * 3, y, 1, 0.8, 0.006); b.rot = r.range(-0.12, 0.12); b.rx = rx; b.ry = ry; st.push(b); y -= ry * 0.88; } return { ...pl, st }; },
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      p.st.forEach((s, i) => { C.blobPath(ctx, s, { sx: s.rx, sy: s.ry, dy: i === p.st.length - 1 ? -0.004 * b : 0 }); fill(ctx, i % 2 ? k.alt : k.main); });
    },
  };

  // 14. Threads: long flowing lines, like wind across grass.
  P.threads = {
    label: 'threads', ground: true, motion: 'flows',
    build: (r, pl, slot) => ({ ...pl, n: slot === 'ground' ? r.int(10, 18) : r.int(6, 10), lines: Array.from({ length: 18 }, () => ({ y: r.next(), amp: r.range(0.02, 0.07), f: r.range(0.6, 1.6), ph: r.range(0, TAU), v: r.range(0.1, 0.25) })), slot }),
    draw(ctx, p, k, t, still) {
      const g = p.slot === 'ground';
      p.lines.slice(0, p.n).forEach((L, i) => {
        const y0 = g ? L.y : p.cy - p.s * 0.6 + L.y * p.s * 1.2, ph = L.ph + (still ? 0 : t * L.v), pts = [];
        for (let x = g ? -0.05 : p.cx - p.s * 1.2; x <= (g ? 1.05 : p.cx + p.s * 1.2); x += 0.015) pts.push([x, y0 + L.amp * Math.sin(TAU * L.f * x + ph) + 0.02 * Math.sin(TAU * 0.4 * x + ph * 0.5)]);
        ctx.beginPath(); pts.forEach(([x, y], j) => (j ? ctx.lineTo(x, y) : ctx.moveTo(x, y))); stroke(ctx, i % 3 ? k.line : k.main, g ? 0.004 : 0.011 - (i % 3) * 0.002, g ? 0.45 : 0.95);
      });
    },
  };

  // 15. Weave: bands over and under, like a cushion cover.
  P.weave = {
    label: 'weave', ground: true, motion: 'a light thread glints along it',
    build: (r, pl, slot) => ({ ...pl, n: r.int(4, 7), w: r.range(0.45, 0.7), slot, tilt: r.range(-0.15, 0.15) }),
    draw(ctx, p, k, t, still) {
      const g = p.slot === 'ground', [x0, y0, S] = g ? [-0.1, -0.1, 1.2] : [p.cx - p.s, p.cy - p.s, p.s * 2], cell = S / p.n, bw = cell * p.w;
      ctx.save(); ctx.translate(p.cx || 0.5, p.cy || 0.5); ctx.rotate(p.tilt); ctx.translate(-(p.cx || 0.5), -(p.cy || 0.5));
      if (!g) { ctx.beginPath(); ctx.rect(x0, y0, S, S); ctx.clip(); }
      const glint = still ? -1 : Math.floor((t * 0.4) % p.n);
      const vb = (i, j0, j1) => { ctx.beginPath(); ctx.rect(x0 + i * cell + (cell - bw) / 2, y0 + j0 * cell, bw, (j1 - j0) * cell); fill(ctx, i === glint ? k.alt : k.main, g ? 0.4 : 1); };
      const hb = (j) => { ctx.beginPath(); ctx.rect(x0, y0 + j * cell + (cell - bw) / 2, S, bw); fill(ctx, j === glint ? k.main : k.alt, g ? 0.4 : 1); };
      for (let i = 0; i < p.n; i++) vb(i, 0, p.n);
      for (let j = 0; j < p.n; j++) hb(j);
      // the vertical band comes back over where the pattern says so
      for (let i = 0; i < p.n; i++) for (let j = 0; j < p.n; j++) if ((i + j) % 2 === 0) { ctx.beginPath(); ctx.rect(x0 + i * cell + (cell - bw) / 2, y0 + j * cell + (cell - bw) / 2 - 0.004, bw, bw + 0.008); fill(ctx, i === glint ? k.alt : k.main, g ? 0.4 : 1); ctx.beginPath(); ctx.moveTo(x0 + i * cell + (cell - bw) / 2, y0 + j * cell + (cell - bw) / 2 - 0.004); ctx.lineTo(x0 + i * cell + (cell + bw) / 2, y0 + j * cell + (cell - bw) / 2 - 0.004); stroke(ctx, k.paper, 0.004, 0.5); }
      ctx.restore();
    },
  };

  // 16. Moon: one moon in phase, or a row of phases; the phase moves slowly.
  P.moon = {
    label: 'moon', motion: 'the phase moves',
    build: (r, pl) => ({ ...pl, kind: r.pick(['one', 'one', 'row']), ph: r.next(), n: r.pick([5, 7]) }),
    draw(ctx, p, k, t, still) {
      const disc = (x, y, R, ph) => {
        C.circle(ctx, x, y, R); fill(ctx, k.main, 0.22);
        const c = Math.cos(ph * TAU); ctx.save(); C.circle(ctx, x, y, R); ctx.clip();
        ctx.beginPath(); ctx.arc(x, y, R, -Math.PI / 2, Math.PI / 2, ph > 0.5); ctx.ellipse(x, y, Math.abs(c) * R, R, 0, Math.PI / 2, -Math.PI / 2, (c > 0) !== (ph > 0.5)); fill(ctx, k.main); ctx.restore();
      };
      const ph = (p.ph + (still ? 0 : t / 400)) % 1;
      if (p.kind === 'one') disc(p.cx, p.cy, p.s * 0.75, ph);
      else { const W = Math.min(p.s * 2.6, 0.76), x0 = C.clamp(p.cx - W / 2, 0.12, 0.88 - W); for (let i = 0; i < p.n; i++) disc(x0 + (i / (p.n - 1)) * W, p.cy, W / 2 / p.n, (ph + i / (p.n - 1) * 0.5) % 1); }
    },
  };

  // 17. Dots: a grid whose sizes ride a slow wave, a soft bokeh, or grain.
  P.dots = {
    label: 'dot rhythm', ground: true, motion: 'a wave passes through',
    build: (r, pl, slot) => ({ ...pl, kind: r.pick(['grid', 'grid', 'bokeh', 'field']), n: r.int(7, 13), fx: r.range(1, 3), fy: r.range(0.5, 2), ph: r.range(0, TAU), b: Array.from({ length: 16 }, () => ({ x: r.next(), y: r.next(), r: r.range(0.03, 0.1), ph: r.range(0, TAU) })), slot }),
    draw(ctx, p, k, t, still) {
      const g = p.slot === 'ground', [x0, y0, S] = g ? [0, 0, 1] : [p.cx - p.s, p.cy - p.s, p.s * 2], ph = p.ph + (still ? 0 : t * 0.4);
      // One path for all the dots: a fill per dot is what makes grids slow.
      const dot = (x, y, r) => { ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, TAU); };
      if (p.kind === 'grid') { const c = S / p.n; ctx.beginPath(); for (let i = 0; i < p.n; i++) for (let j = 0; j < p.n; j++) { const v = 0.5 + 0.5 * Math.sin(p.fx * i / p.n * TAU + p.fy * j / p.n * TAU - ph); dot(x0 + (i + 0.5) * c, y0 + (j + 0.5) * c, c * 0.42 * (0.15 + 0.85 * v)); } fill(ctx, g ? k.line : k.main, g ? 0.35 : 0.9); }
      else if (p.kind === 'bokeh') p.b.forEach((q) => soft(ctx, x0 + q.x * S, y0 + q.y * S, q.r * S * 1.3, (q.ph > 3 ? k.alt : k.glow), 0.5 * (0.7 + 0.3 * Math.sin(ph + q.ph))));
      else { const R = C.makeRng('field'); ctx.beginPath(); for (let i = 0; i < 260; i++) { const x = x0 + R.next() * S, y = y0 + R.next() * S; dot(x, y, R.range(0.002, 0.006) * (1 + 0.5 * Math.sin(ph + x * 9))); } fill(ctx, g ? k.line : k.main, 0.6); }
    },
  };

  // 18. Hills: two to four cut-paper ridges, drifting in parallax.
  P.hills = {
    label: 'cut-paper hills', ground: true, motion: 'ridges drift in parallax',
    build: (r, pl) => ({ ...pl, layers: Array.from({ length: r.int(2, 4) }, (_, i) => ({ y: r.range(0.5, 0.62) + i * r.range(0.07, 0.11), amp: r.range(0.03, 0.09), f: r.range(0.5, 1.6), ph: r.range(0, TAU), rr: C.makeRng('h' + r.next()) })) }),
    draw(ctx, p, k, t, still) {
      const n = p.layers.length;
      p.layers.forEach((L, i) => {
        const dr = still ? 0 : 0.015 * (i + 1) * Math.sin(t / 25), pts = [[-0.1, 1.1]];
        for (let x = -0.1; x <= 1.1; x += 0.05) pts.push([x, L.y - L.amp * (0.6 + 0.4 * Math.sin(TAU * L.f * (x + dr) + L.ph))]);
        pts.push([1.1, 1.1]); C.cutPoly(ctx, pts, C.makeRng('hill' + i + L.ph), 0.004);
        fill(ctx, mix(k.alt, k.main, n === 1 ? 1 : i / (n - 1)));
      });
    },
  };

  // 19. Sun: a disc with rays, wedges or lines, turning slowly.
  P.sun = {
    label: 'sun and rays', motion: 'rays turn slowly',
    build: (r, pl) => ({ ...pl, n: r.pick([8, 12, 16, 24]), kind: r.pick(['lines', 'wedges', 'dashes']), len: r.range(0.5, 0.9) }),
    draw(ctx, p, k, t, still) {
      const rot = still ? 0 : t / 200 * TAU, b = BR(t, still), R = p.s * 0.45;
      for (let i = 0; i < p.n; i++) {
        const a = i / p.n * TAU + rot, r0 = R * 1.25, r1 = R * (1.3 + p.len * (i % 2 ? 0.7 : 1)) * (0.95 + 0.05 * b);
        if (p.kind === 'wedges') { ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a - 0.08) * r0, p.cy + Math.sin(a - 0.08) * r0); ctx.lineTo(p.cx + Math.cos(a) * r1, p.cy + Math.sin(a) * r1); ctx.lineTo(p.cx + Math.cos(a + 0.08) * r0, p.cy + Math.sin(a + 0.08) * r0); ctx.closePath(); fill(ctx, k.alt); }
        else { if (p.kind === 'dashes') ctx.setLineDash([0.02, 0.015]); ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * r0, p.cy + Math.sin(a) * r0); ctx.lineTo(p.cx + Math.cos(a) * r1, p.cy + Math.sin(a) * r1); stroke(ctx, k.alt, 0.008); ctx.setLineDash([]); }
      }
      C.circle(ctx, p.cx, p.cy, R); fill(ctx, k.main);
    },
  };

  // 20. Stack: cut-paper cards piled a little askew.
  P.stack = {
    label: 'stack', motion: 'the top card lifts on the breath',
    build: (r, pl) => ({ ...pl, cards: Array.from({ length: r.int(4, 7) }, (_, i) => ({ dx: r.range(-0.05, 0.05), dy: -i * r.range(0.035, 0.05), rot: r.range(-0.12, 0.12), w: r.range(1.1, 1.4), h: r.range(0.32, 0.5), rr: C.makeRng('card' + r.next()) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), n = p.cards.length;
      p.cards.forEach((c, i) => {
        ctx.save(); ctx.translate(p.cx + c.dx * p.s * 3, p.cy + p.s * 0.3 + c.dy * p.s * 3 - (i === n - 1 ? 0.01 * b : 0)); ctx.rotate(c.rot);
        const w = c.w * p.s / 2, h = c.h * p.s / 2; C.cutPoly(ctx, [[-w, -h], [w, -h], [w, h], [-w, h]], c.rr, 0.003);
        fill(ctx, i % 2 ? k.alt : k.main); stroke(ctx, k.paper, 0.004, 0.7); ctx.restore();
      });
    },
  };

  // 21. Grove: a row of trees cut from paper, swaying.
  P.grove = {
    label: 'grove', ground: true, motion: 'sways',
    build: (r, pl) => ({ ...pl, trees: Array.from({ length: r.int(4, 9) }, () => ({ x: r.range(0.04, 0.96), h: r.range(0.14, 0.32), kind: r.pick(['pine', 'round', 'pine']), z: r.next() })).sort((a, b) => a.z - b.z), base: r.range(0.7, 0.82) }),
    draw(ctx, p, k, t, still) {
      for (const tr of p.trees) {
        const sw = still ? 0 : 0.006 * Math.sin(t * 0.6 + tr.x * 9), b = p.base + tr.z * 0.06, col = mix(k.alt, k.main, tr.z);
        if (tr.kind === 'pine') C.cutPoly(ctx, [[tr.x + sw, b - tr.h], [tr.x + tr.h * 0.3, b], [tr.x - tr.h * 0.3, b]], C.makeRng('t' + tr.x), 0.003);
        else { ctx.beginPath(); ctx.moveTo(tr.x, b); ctx.lineTo(tr.x + sw, b - tr.h * 0.4); stroke(ctx, col, 0.008); C.circle(ctx, tr.x + sw, b - tr.h * 0.62, tr.h * 0.3); }
        fill(ctx, col);
      }
      ctx.fillStyle = css(k.main); ctx.fillRect(0, p.base + 0.05, 1, 1);
    },
  };

  // 22. Disc: one plain round body (sun, moon, bindu), breathing between a
  // true circle and its pebble shape. The quietest accent.
  P.disc = {
    label: 'disc', motion: 'breathes between round and pebble',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy, pl.s * 0.6, 0.7, 0.003) }),
    draw(ctx, p, k, t, still) { const b = BR(t, still); C.blobPath(ctx, p.blob, { imperf: 1 - b, grow: 0.95 + 0.05 * b }); fill(ctx, k.main); },
  };

  return P;
})();
