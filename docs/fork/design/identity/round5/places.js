/* Round 5 additions, loaded after round 4's grounds.js and prims.js, which
 * stay untouched so every approved card is unchanged.
 *
 *   - grounds for the modern places: window, balcony, terrace, car, metro
 *     carriage, room;
 *   - figures for them: lamp, window, cup, porthole, fan, umbrella, railing,
 *     droplets, strap, doorway;
 *   - a bell figure for each bell that ships (PR #34), drawn from the five
 *     controls of its sound (bells.json), struck once on preview and still
 *     otherwise;
 *   - the noise texture in its own colour (white, pink, brown).
 * Same contracts as round 4 (see grounds.js and prims.js). */
(() => {
  'use strict';
  const C = Core, { TAU, lerp, css, mix } = C;
  const S = (t, period, ph = 0) => Math.sin(TAU * t / period + ph);
  const BR = (t, still, ph = 0) => (still ? 0.5 : 0.5 - 0.5 * Math.cos(TAU * t / C.BREATH + ph));
  const fade = (u) => Math.sin(Math.PI * C.clamp(u, 0, 1));
  const vgrad = (ctx, y0, y1, stops) => { const g = ctx.createLinearGradient(0, y0, 0, y1); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); return g; };
  const glow = (ctx, x, y, r, col, a) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(0.5, css(col, a * 0.35)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  const fill = (ctx, col, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = css(col); ctx.fill(); ctx.globalAlpha = 1; };
  const stroke = (ctx, col, w, a = 1) => { ctx.globalAlpha = a; ctx.strokeStyle = css(col); ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); ctx.globalAlpha = 1; };
  const rr = (ctx, x, y, w, h, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };
  const dark = (c, k) => mix(c.deep, c.form, k);
  const G = Grounds, P = Prims;

  // A droplet on glass: body, a darker lower rim, one highlight.
  function bead(ctx, x, y, r, k, a = 1) {
    C.circle(ctx, x, y, r); fill(ctx, k.light || k.glow, 0.28 * a);
    ctx.beginPath(); ctx.arc(x, y, r, 0.2, Math.PI - 0.2); stroke(ctx, k.dark || k.line, r * 0.35, 0.45 * a);
    C.circle(ctx, x - r * 0.35, y - r * 0.35, r * 0.28); fill(ctx, '#ffffff', 0.55 * a);
  }

  // ================= grounds =================

  // Looking out through a window from a dim room: the frame, blurred lights
  // outside, rain beading and trickling down the glass.
  G.window = {
    label: 'window', motion: 'drops trickle down the glass; the lights outside breathe',
    build: (r) => ({ x: r.range(0.12, 0.18), y: r.range(0.1, 0.15), w: r.range(0.64, 0.74), h: r.range(0.66, 0.74), mull: r.pick(['cross', 'vertical', 'none']), out: r.pick(['grey', 'dusk', 'night']),
      lights: Array.from({ length: 9 }, () => ({ x: r.next(), y: r.range(0.35, 0.95), r: r.range(0.03, 0.08), ph: r.range(0, TAU), role: r.pick(['accent', 'light', 'accent']) })),
      beads: Array.from({ length: 34 }, () => ({ x: r.next(), y: r.next(), r: r.range(0.004, 0.012) })),
      runs: Array.from({ length: 6 }, () => ({ x: r.next(), y: r.next(), v: r.range(0.025, 0.05), len: r.range(0.06, 0.16) })) }),
    tone: (c, p) => (p.out === 'grey' ? mix(c.tile, c.form, 0.45) : p.out === 'dusk' ? mix(c.accent, c.deep, 0.45) : mix(c.deep, c.form, 0.25)),
    draw(ctx, p, c, t, still, H) {
      ctx.fillStyle = vgrad(ctx, 0, H, [[0, mix(c.deep, c.form, 0.15)], [1, mix(c.deep, c.accent, 0.1)]]); ctx.fillRect(0, 0, 1, H);
      glow(ctx, 0.1, H * 0.95, 0.5, c.accent, 0.22);
      const x0 = p.x, y0 = p.y * H, w = p.w, h = p.h * H;
      ctx.save(); rr(ctx, x0, y0, w, h, 0.02); ctx.clip();
      ctx.fillStyle = vgrad(ctx, y0, y0 + h, [[0, mix(G.window.tone(c, p), c.tile, 0.15)], [1, G.window.tone(c, p)]]); ctx.fillRect(x0, y0, w, h);
      for (const L of p.lights) glow(ctx, x0 + L.x * w, y0 + L.y * h, L.r, c[L.role], 0.45 * (still ? 1 : 0.8 + 0.2 * S(t, 10, L.ph)));
      const kk = { light: c.light, dark: c.deep };
      for (const b of p.beads) bead(ctx, x0 + b.x * w, y0 + b.y * h, b.r, kk, 0.9);
      for (const q of p.runs) { const u = still ? q.y : (q.y + t * q.v) % 1, y = y0 + u * h, x = x0 + q.x * w; ctx.beginPath(); ctx.moveTo(x, y - q.len * h * 0.6); ctx.lineTo(x + 0.002, y); stroke(ctx, c.light, 0.003, 0.35 * fade(u)); bead(ctx, x, y, 0.009, kk, fade(u)); }
      ctx.restore();
      const frame = mix(c.deep, c.tile, 0.22);
      rr(ctx, x0, y0, w, h, 0.02); stroke(ctx, frame, 0.03);
      ctx.beginPath(); if (p.mull !== 'none') { ctx.moveTo(x0 + w / 2, y0); ctx.lineTo(x0 + w / 2, y0 + h); } if (p.mull === 'cross') { ctx.moveTo(x0, y0 + h * 0.45); ctx.lineTo(x0 + w, y0 + h * 0.45); } stroke(ctx, frame, 0.018);
      ctx.fillStyle = css(mix(frame, c.light, 0.15)); ctx.fillRect(x0 - 0.03, y0 + h + 0.01, w + 0.06, 0.03);
    },
  };

  // A balcony railing against a rainy or dusk sky, with a far skyline. Its
  // "terrace" variant (a parapet over a floor with puddles) was too close to
  // the balcony; no class uses it now, and the terrace has its own ground
  // below. It stays so the variant field in frozen params keeps its meaning.
  G.balcony = {
    label: 'balcony or terrace', motion: 'rain falls past the rail; puddles and windows shimmer',
    build: (r, o) => ({ variant: o.variant || r.pick(['balcony', 'terrace']), sky: r.pick(['rain', 'rain', 'dusk']), rail: r.range(0.6, 0.68), bal: r.int(7, 12),
      city: Array.from({ length: r.int(8, 14) }, () => ({ w: r.range(0.05, 0.12), h: r.range(0.08, 0.28), lit: Array.from({ length: 4 }, () => [r.next(), r.next(), r.range(0, TAU)]) })),
      drops: Array.from({ length: 45 }, () => ({ x: r.range(-0.1, 1.1), y: r.next(), l: r.range(0.04, 0.09), v: r.range(0.06, 0.1), a: r.range(0.15, 0.4) })),
      pud: Array.from({ length: 3 }, () => ({ x: r.range(0.2, 0.8), w: r.range(0.12, 0.24), ph: r.range(0, TAU) })) }),
    tone: (c, p) => (p.sky === 'dusk' ? mix(c.accent, c.form, 0.5) : mix(c.tile, c.form, 0.5)),
    draw(ctx, p, c, t, still, H) {
      const sky = p.sky === 'dusk' ? [mix(c.form, c.deep, 0.3), mix(c.accent, c.tile, 0.3)] : [mix(c.form, c.deep, 0.25), mix(c.tile, c.form, 0.35)];
      ctx.fillStyle = vgrad(ctx, 0, H, [[0, sky[0]], [0.6, sky[1]], [1, sky[1]]]); ctx.fillRect(0, 0, 1, H);
      const horizon = p.rail * H - 0.02; let x = -0.02;
      for (const b of p.city) { const top = horizon - b.h * H; ctx.fillStyle = css(mix(c.form, c.deep, 0.45), 0.8); ctx.fillRect(x, top, b.w, horizon - top + 0.05); for (const [lx, ly, ph] of b.lit) { ctx.fillStyle = css(c.accent, still ? 0.6 : 0.4 + 0.3 * S(t, 9, ph)); ctx.fillRect(x + lx * (b.w - 0.012), top + ly * (horizon - top) * 0.8, 0.008, 0.01); } x += b.w + 0.005; }
      ctx.lineCap = 'round'; ctx.lineWidth = 0.003;
      if (p.sky === 'rain') for (const d of p.drops) { const y = ((d.y + (still ? 0 : t * d.v)) % 1.15 - 0.1) * H; ctx.strokeStyle = css(c.light, d.a); ctx.beginPath(); ctx.moveTo(d.x, y); ctx.lineTo(d.x - d.l * 0.1, y + d.l * H); ctx.stroke(); }
      const ink = mix(c.deep, c.form, 0.1), ry = p.rail * H;
      if (p.variant === 'balcony') {
        ctx.fillStyle = css(ink); ctx.fillRect(-0.05, ry, 1.1, 0.022); ctx.fillRect(-0.05, H - 0.07, 1.1, 0.07);
        for (let i = 0; i < p.bal; i++) { const bx = (i + 0.5) / p.bal; ctx.fillRect(bx - 0.006, ry, 0.012, H - ry - 0.06); }
        for (let i = 0; i < p.bal * 2; i++) bead(ctx, (i + 0.3) / (p.bal * 2), ry + 0.026, 0.005, { light: c.light, dark: c.deep }, 0.8);
      } else {
        ctx.fillStyle = css(ink); ctx.fillRect(-0.05, ry, 1.1, 0.07);
        ctx.fillStyle = vgrad(ctx, ry + 0.07, H, [[0, mix(c.form, c.deep, 0.55)], [1, mix(c.form, c.deep, 0.35)]]); ctx.fillRect(0, ry + 0.07, 1, H);
        ctx.strokeStyle = css(c.light, 0.12); ctx.lineWidth = 0.003; for (let i = 1; i < 6; i++) { const y = ry + 0.07 + (H - ry - 0.07) * Math.pow(i / 6, 1.4); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(1, y); ctx.stroke(); }
        for (const q of p.pud) { ctx.beginPath(); ctx.ellipse(q.x, H * 0.9, q.w, 0.02, 0, 0, TAU); ctx.fillStyle = css(mix(sky[1], c.light, 0.2), still ? 0.45 : 0.35 + 0.15 * S(t, 8, q.ph)); ctx.fill(); }
      }
    },
  };

  // A terrace, its own place (round 5 follow-up; balcony keeps the skyline).
  // Three ways to be there:
  //   tiles: looking down on wet stone or terracotta, puddles with rings
  //          opening in them, a potted plant or two;
  //   eave:  under the eave, drops running off its edge in a line, a garden
  //          beyond in the rain;
  //   court: a walled roof garden at evening, rain on the paving, a lamp's
  //          warm light in it.
  const fr = (x) => x - Math.floor(x);
  const hsh = (n) => fr(Math.sin(n * 127.1 + 311.7) * 43758.5453);
  function pond(ctx, x, y, R, harm, sq = 1) { // a soft puddle outline
    ctx.beginPath();
    for (let i = 0; i <= 48; i++) { const a = (i / 48) * TAU; let r = R; for (const [k, amp, ph] of harm) r += R * amp * Math.sin(k * a + ph); const px = x + Math.cos(a) * r, py = y + Math.sin(a) * r * sq; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); }
    ctx.closePath();
  }
  // Rain rings: each slot opens a ring, fades, and reappears elsewhere in
  // its puddle while unseen.
  function rainRings(ctx, q, n, col, t, still, sq = 1, speed = 1) {
    if (still) return;
    for (let i = 0; i < n; i++) {
      const per = 1.6 + hsh(q.seed + i) * 1.4, raw = t * speed / per + hsh(q.seed * 3 + i), cyc = Math.floor(raw), u = raw - cyc;
      const a = hsh(q.seed + i * 7 + cyc * 13) * TAU, d = Math.sqrt(hsh(q.seed + i * 5 + cyc * 17)) * q.r * 0.65;
      const x = q.x + Math.cos(a) * d, y = q.y + Math.sin(a) * d * sq, rr0 = q.r * (0.05 + 0.3 * u);
      ctx.beginPath(); ctx.ellipse(x, y, rr0, rr0 * sq, 0, 0, TAU); stroke(ctx, col, 0.005, 0.9 * Math.pow(1 - u, 1.5));
      if (u > 0.25) { const r1 = q.r * (0.05 + 0.3 * (u - 0.25)); ctx.beginPath(); ctx.ellipse(x, y, r1, r1 * sq, 0, 0, TAU); stroke(ctx, col, 0.0035, 0.65 * Math.pow(1 - u, 1.5)); }
    }
  }
  function potFromAbove(ctx, x, y, R, leaves, c, t, still, ph) {
    C.circle(ctx, x + R * 0.12, y + R * 0.14, R * 1.05); fill(ctx, c.deep, 0.3);
    C.circle(ctx, x, y, R); fill(ctx, mix(c.accent, c.deep, 0.3));
    C.circle(ctx, x, y, R * 0.82); fill(ctx, mix(c.deep, c.form, 0.15));
    const sw = still ? 0 : 0.04 * S(t, 7, ph);
    for (let i = 0; i < leaves; i++) {
      const a = (i / leaves) * TAU + ph + sw * (i % 2 ? 1 : -1), L = R * (1.15 + 0.35 * hsh(ph * 10 + i));
      ctx.save(); ctx.translate(x, y); ctx.rotate(a);
      ctx.beginPath(); ctx.ellipse(L * 0.55, 0, L * 0.55, R * 0.22, 0, 0, TAU); fill(ctx, mix(c.form, c.deep, 0.35 + 0.25 * (i % 2)));
      ctx.beginPath(); ctx.moveTo(R * 0.1, 0); ctx.lineTo(L * 0.95, 0); stroke(ctx, c.light, 0.002, 0.25);
      ctx.restore();
    }
  }
  G.terrace = {
    label: 'terrace', motion: 'rings open in the puddles; drops run off the eave; the garden breathes',
    build: (r, o) => {
      const variant = o.variant || r.pick(['tiles', 'eave', 'court']);
      return {
        variant, stone: r.chance(0.5), n: r.int(4, 6), ang: r.range(-0.22, 0.22), shade: Array.from({ length: 64 }, () => r.range(-1, 1)),
        pud: Array.from({ length: r.int(2, 3) }, (_, i) => ({ x: r.range(0.2, 0.8), y: r.range(0.25, 0.85), r: r.range(0.1, 0.17), seed: r.range(1, 99) + i, harm: [[2, r.range(0.06, 0.14), r.range(0, TAU)], [3, r.range(0.04, 0.1), r.range(0, TAU)], [5, r.range(0.02, 0.05), r.range(0, TAU)]] })),
        pots: Array.from({ length: 2 }, (_, i) => ({ x: i ? r.range(0.74, 0.84) : r.range(0.16, 0.26), y: i ? r.range(0.72, 0.82) : r.range(0.16, 0.26), r: i ? r.range(0.07, 0.09) : r.range(0.1, 0.13), leaves: r.int(7, 11), ph: r.range(0, TAU) })),
        eave: r.range(0.2, 0.26), drips: r.int(11, 16), dseed: r.range(1, 99), beam: r.chance(0.5),
        hedge: Array.from({ length: 7 }, () => ({ x: r.next(), w: r.range(0.12, 0.26), h: r.range(0.06, 0.16) })),
        trees: Array.from({ length: r.int(2, 3) }, () => ({ x: r.range(0.1, 0.9), r: r.range(0.08, 0.14), h: r.range(0.12, 0.22) })),
        drops: Array.from({ length: 40 }, () => ({ x: r.next(), y: r.next(), l: r.range(0.03, 0.07), v: r.range(0.07, 0.11), a: r.range(0.12, 0.3) })),
        wall: r.range(0.5, 0.58), lamp: r.range(0.25, 0.75), cypress: r.range(0.1, 0.3), bushes: Array.from({ length: 4 }, () => ({ x: r.next(), r: r.range(0.04, 0.07) })),
      };
    },
    tone: (c, p) => (p.variant === 'tiles' ? (p.stone ? mix(c.tile, c.form, 0.45) : mix(c.accent, c.deep, 0.35)) : p.variant === 'court' ? mix(c.accent, c.form, 0.45) : mix(c.tile, c.form, 0.45)),
    draw(ctx, p, c, t, still, H) {
      const ink = mix(c.deep, c.form, 0.1);
      if (p.variant === 'tiles') {
        const base = p.stone ? mix(c.tile, c.form, 0.45) : mix(c.accent, c.deep, 0.3), grout = mix(base, c.deep, 0.45), ts = 1 / p.n;
        ctx.fillStyle = css(grout); ctx.fillRect(0, 0, 1, H);
        ctx.save(); ctx.translate(0.5, H / 2); ctx.rotate(p.ang); ctx.translate(-0.5, -H / 2);
        let k = 0;
        for (let iy = -2; iy < p.n * H + 2; iy++) for (let ix = -2; ix < p.n + 2; ix++) {
          const v = p.shade[(k++) % p.shade.length], off = !p.stone && iy % 2 ? ts / 2 : 0, x = ix * ts + off, y = iy * ts;
          rr(ctx, x + 0.004, y + 0.004, ts - 0.008, ts - 0.008, 0.006); ctx.fillStyle = css(mix(base, v > 0 ? c.light : c.deep, Math.abs(v) * 0.12)); ctx.fill();
        }
        ctx.restore();
        // the wet sheen: a slow broad light across the tiles
        const g = ctx.createLinearGradient(0, 0, 1, H); g.addColorStop(0, css(c.light, 0)); g.addColorStop(0.45 + (still ? 0 : 0.05 * S(t, 12)), css(c.light, 0.12)); g.addColorStop(0.7, css(c.light, 0)); ctx.fillStyle = g; ctx.fillRect(0, 0, 1, H);
        for (const q of p.pud) {
          const Q = { ...q, y: q.y * H };
          pond(ctx, Q.x, Q.y, q.r, q.harm); fill(ctx, mix(base, c.deep, 0.4), 0.55);
          pond(ctx, Q.x, Q.y, q.r * 0.9, q.harm); fill(ctx, mix(c.tile, c.light, 0.35), 0.4);
          pond(ctx, Q.x, Q.y, q.r, q.harm); stroke(ctx, mix(base, c.deep, 0.5), 0.004, 0.5);
          ctx.save(); pond(ctx, Q.x, Q.y, q.r, q.harm); ctx.clip(); rainRings(ctx, Q, 3, c.light, t, still); ctx.restore();
        }
        // a few splashes on the open tiles
        if (!still) for (let i = 0; i < 10; i++) { const raw = t / 0.9 + hsh(i + 3.3), cyc = Math.floor(raw), u = raw - cyc, x = hsh(i * 9 + cyc * 3.7), y = hsh(i * 4 + cyc * 5.1) * H; ctx.beginPath(); ctx.arc(x, y, 0.004 + 0.012 * u, 0, TAU); stroke(ctx, c.light, 0.002, 0.45 * (1 - u)); }
        for (const q of p.pots) potFromAbove(ctx, q.x, q.y * H, q.r, q.leaves, c, t, still, q.ph);
      } else if (p.variant === 'eave') {
        const eY = p.eave * H, floor = H * 0.8, haze = mix(c.tile, c.form, 0.4);
        ctx.fillStyle = vgrad(ctx, 0, H, [[0, mix(c.tile, c.form, 0.55)], [0.75, haze], [1, haze]]); ctx.fillRect(0, 0, 1, H);
        for (const tr of p.trees) { const y = H * 0.7; ctx.beginPath(); ctx.moveTo(tr.x, y); ctx.lineTo(tr.x, y - tr.h * H); stroke(ctx, mix(c.form, c.deep, 0.5), 0.008, 0.6); ctx.beginPath(); ctx.ellipse(tr.x, y - tr.h * H * 1.3, tr.r, tr.h * H * 0.7, 0, 0, TAU); fill(ctx, mix(c.form, c.deep, 0.3), 0.6); }
        for (const h of p.hedge) { ctx.beginPath(); ctx.ellipse(h.x, H * 0.7, h.w, h.h * H, 0, Math.PI, TAU); fill(ctx, mix(c.form, c.deep, 0.4), 0.75); }
        ctx.fillStyle = css(mix(c.form, c.deep, 0.45)); ctx.fillRect(0, H * 0.7 - 0.002, 1, floor - H * 0.7);
        ctx.lineCap = 'round';
        for (const d of p.drops) { const y = eY + ((d.y + (still ? 0 : t * d.v)) % 1) * (floor - eY); ctx.strokeStyle = css(c.light, d.a * 0.8); ctx.lineWidth = 0.002; ctx.beginPath(); ctx.moveTo(d.x, y); ctx.lineTo(d.x - 0.004, y + d.l * H * 0.6); ctx.stroke(); }
        // the terrace floor, wet, in perspective
        ctx.fillStyle = vgrad(ctx, floor, H, [[0, mix(c.deep, c.form, 0.35)], [1, mix(c.deep, c.form, 0.15)]]); ctx.fillRect(0, floor, 1, H - floor);
        for (let i = -6; i <= 6; i++) { ctx.beginPath(); ctx.moveTo(0.5 + i * 0.05, floor); ctx.lineTo(0.5 + i * 0.28, H); stroke(ctx, c.light, 0.002, 0.12); }
        for (let i = 1; i < 4; i++) { const y = floor + (H - floor) * Math.pow(i / 4, 1.6); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(1, y); stroke(ctx, c.light, 0.002, 0.12); }
        // the eave and its line of drops
        ctx.fillStyle = css(ink); ctx.fillRect(-0.05, 0, 1.1, eY);
        if (p.beam) for (let i = 0; i < 6; i++) { ctx.beginPath(); ctx.moveTo((i + 0.5) / 6, 0); ctx.lineTo((i + 0.5) / 6, eY - 0.01); stroke(ctx, mix(ink, c.light, 0.12), 0.012); }
        ctx.fillStyle = css(mix(ink, c.light, 0.2)); ctx.fillRect(-0.05, eY - 0.03, 1.1, 0.03);
        ctx.beginPath(); ctx.moveTo(-0.05, eY - 0.03); ctx.lineTo(1.05, eY - 0.03); stroke(ctx, c.light, 0.003, 0.35);
        const kk = { light: c.light, dark: c.deep };
        for (let i = 0; i < p.drips; i++) {
          const x = (i + 0.5 + (hsh(p.dseed + i) - 0.5) * 0.5) / p.drips, per = 1.1 + hsh(p.dseed + i * 3) * 1.2, raw = (still ? 0.3 : t / per) + hsh(p.dseed * 2 + i), u = fr(raw);
          bead(ctx, x, eY + 0.008, 0.005 + 0.006 * Math.min(1, u / 0.6), kk, 1);
          if (!still && u > 0.6) { const f = (u - 0.6) / 0.4, y = eY + 0.012 + f * f * (floor - eY + 0.06); ctx.beginPath(); ctx.moveTo(x, y - 0.07 * f); ctx.lineTo(x, y); stroke(ctx, c.light, 0.004, 0.85); bead(ctx, x, y, 0.006, kk, 1); }
          if (!still && u < 0.25) { const f = u / 0.25; ctx.beginPath(); ctx.ellipse(x, floor + 0.06, 0.006 + 0.04 * f, (0.006 + 0.04 * f) * 0.3, 0, 0, TAU); stroke(ctx, c.light, 0.003, 0.7 * (1 - f)); }
        }
      } else {
        const wy = p.wall * H, warm = mix(c.accent, c.light, 0.3);
        ctx.fillStyle = vgrad(ctx, 0, wy, [[0, mix(c.form, c.deep, 0.35)], [1, mix(c.accent, c.form, 0.4)]]); ctx.fillRect(0, 0, 1, wy);
        ctx.lineCap = 'round';
        for (const d of p.drops) { const y = ((d.y + (still ? 0 : t * d.v)) % 1) * H; ctx.strokeStyle = css(c.light, d.a * 0.7); ctx.lineWidth = 0.002; ctx.beginPath(); ctx.moveTo(d.x, y); ctx.lineTo(d.x - 0.006, y + d.l * H * 0.6); ctx.stroke(); }
        // a cypress and shrubs behind the low wall
        ctx.beginPath(); ctx.ellipse(p.cypress, wy - 0.2, 0.045, 0.24, 0, 0, TAU); fill(ctx, mix(c.form, c.deep, 0.55));
        for (const b of p.bushes) { C.circle(ctx, b.x, wy - b.r * 0.4, b.r); fill(ctx, mix(c.form, c.deep, 0.45)); }
        // the low wall with its coping, and a lamp on it
        ctx.fillStyle = css(mix(c.deep, c.accent, 0.2)); ctx.fillRect(0, wy, 1, 0.12);
        ctx.fillStyle = css(mix(c.deep, c.light, 0.18)); ctx.fillRect(0, wy - 0.012, 1, 0.014);
        const lx = p.lamp, br = still ? 1 : 0.9 + 0.1 * BR(t, false);
        glow(ctx, lx, wy - 0.035, 0.22 * br, warm, 0.45);
        rr(ctx, lx - 0.016, wy - 0.06, 0.032, 0.048, 0.006); fill(ctx, warm, 0.95);
        // wet paving with the lamp's reflection
        const fy = wy + 0.12;
        ctx.fillStyle = vgrad(ctx, fy, H, [[0, mix(c.deep, c.form, 0.3)], [1, mix(c.deep, c.accent, 0.12)]]); ctx.fillRect(0, fy, 1, H - fy);
        for (let i = 1; i < 5; i++) { const y = fy + (H - fy) * Math.pow(i / 5, 1.5); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(1, y); stroke(ctx, c.light, 0.002, 0.1); }
        for (let i = -5; i <= 5; i++) { ctx.beginPath(); ctx.moveTo(0.5 + i * 0.08, fy); ctx.lineTo(0.5 + i * 0.3, H); stroke(ctx, c.light, 0.002, 0.1); }
        for (let j = 0; j < 9; j++) { const y = fy + 0.02 + j * (H - fy) / 10, w = 0.02 + 0.006 * j, a = 0.35 * (1 - j / 10) * (still ? 1 : 0.8 + 0.2 * S(t, 2.5, j)); ctx.fillStyle = css(warm, a); ctx.fillRect(lx - w / 2 + (still ? 0 : 0.004 * S(t, 1.7, j * 1.3)), y, w, 0.008); }
        const Q = { x: 1 - lx * 0.8, y: fy + (H - fy) * 0.55, r: 0.12, seed: p.dseed };
        rainRings(ctx, Q, 4, c.light, t, still, 0.3);
      }
    },
  };

  // The view from a parked car in the rain: the roof's dark edge, the
  // dashboard's curve, lights blurred beyond the glass, beads sliding.
  G.car = {
    label: 'car in the rain', motion: 'beads slide slowly up and across the windscreen',
    build: (r) => ({ lights: Array.from({ length: 10 }, () => ({ x: r.next(), y: r.range(0.3, 0.7), r: r.range(0.03, 0.09), ph: r.range(0, TAU), role: r.pick(['accent', 'accent', 'light']) })), beads: Array.from({ length: 40 }, () => ({ x: r.next(), y: r.range(0.18, 0.78), r: r.range(0.004, 0.011) })), runs: Array.from({ length: 7 }, () => ({ x: r.next(), y: r.next(), v: r.range(0.02, 0.04), a: r.range(-0.6, -0.2) })), dash: r.range(0.78, 0.84) }),
    tone: (c) => mix(c.deep, c.form, 0.2),
    draw(ctx, p, c, t, still, H) {
      ctx.fillStyle = vgrad(ctx, 0, H, [[0, mix(c.deep, c.form, 0.1)], [0.55, mix(c.deep, c.form, 0.35)], [1, c.deep]]); ctx.fillRect(0, 0, 1, H);
      for (const L of p.lights) glow(ctx, L.x, L.y * H, L.r, c[L.role], 0.5 * (still ? 1 : 0.8 + 0.2 * S(t, 11, L.ph)));
      const kk = { light: c.light, dark: c.deep };
      for (const b of p.beads) bead(ctx, b.x, b.y * H, b.r, kk, 0.85);
      for (const q of p.runs) { const u = still ? q.y : (q.y + t * q.v) % 1, x = q.x + u * 0.12, y = H * (0.75 - u * 0.55); bead(ctx, x, y, 0.01, kk, fade(u)); ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 0.03, y + 0.06); stroke(ctx, c.light, 0.002, 0.25 * fade(u)); }
      ctx.beginPath(); ctx.moveTo(-0.05, 0); ctx.lineTo(1.05, 0); ctx.lineTo(1.05, H * 0.12); ctx.quadraticCurveTo(0.5, H * 0.22, -0.05, H * 0.12); ctx.closePath(); fill(ctx, c.deep);
      ctx.beginPath(); ctx.moveTo(-0.05, H); ctx.lineTo(-0.05, H * (p.dash - 0.04)); ctx.quadraticCurveTo(0.5, H * (p.dash - 0.1), 1.05, H * (p.dash - 0.04)); ctx.lineTo(1.05, H); ctx.closePath(); fill(ctx, c.deep);
      ctx.beginPath(); ctx.moveTo(0.05, H * (p.dash - 0.05)); ctx.quadraticCurveTo(0.5, H * (p.dash - 0.11), 0.95, H * (p.dash - 0.05)); stroke(ctx, c.light, 0.003, 0.18);
    },
  };

  // Inside a carriage: the window band with lights streaming past, wall
  // panels, a rail and a pole; the whole car sways a little.
  G.metro = {
    label: 'metro carriage', motion: 'lights stream past the windows; the carriage sways',
    build: (r) => ({ by: r.range(0.3, 0.38), bh: r.range(0.24, 0.3), lights: Array.from({ length: 12 }, () => ({ x: r.next(), y: r.next(), len: r.range(0.08, 0.3), v: r.range(0.12, 0.3), role: r.pick(['accent', 'light', 'accent', 'form']) })), pole: r.range(0.18, 0.82), day: r.chance(0.3) }),
    tone: (c) => mix(c.tile, c.form, 0.45),
    draw(ctx, p, c, t, still, H) {
      const sway = still ? 0 : 0.004 * S(t, 4.3);
      ctx.save(); ctx.translate(0, sway);
      ctx.fillStyle = css(mix(c.tile, c.form, 0.3)); ctx.fillRect(0, -0.02, 1, H + 0.04);
      ctx.fillStyle = css(mix(c.form, c.deep, 0.35)); ctx.fillRect(0, (p.by + p.bh + 0.06) * H, 1, H);
      const y0 = p.by * H, h = p.bh * H;
      ctx.save(); rr(ctx, 0.04, y0, 0.92, h, 0.03); ctx.clip();
      ctx.fillStyle = vgrad(ctx, y0, y0 + h, [[0, p.day ? mix(c.tile, c.form, 0.4) : c.deep], [1, p.day ? mix(c.form, c.tile, 0.3) : mix(c.deep, c.form, 0.25)]]); ctx.fillRect(0, y0, 1, h);
      ctx.lineCap = 'round';
      for (const L of p.lights) { const x = 1.3 - (((L.x + (still ? 0 : t * L.v)) % 1.6)), y = y0 + h * (0.15 + 0.7 * L.y); const g = ctx.createLinearGradient(x, 0, x + L.len, 0); g.addColorStop(0, css(c[L.role], 0)); g.addColorStop(0.3, css(c[L.role], 0.75)); g.addColorStop(1, css(c[L.role], 0)); ctx.strokeStyle = g; ctx.lineWidth = 0.008; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + L.len, y); ctx.stroke(); }
      ctx.restore();
      rr(ctx, 0.04, y0, 0.92, h, 0.03); stroke(ctx, mix(c.tile, c.light, 0.3), 0.012);
      ctx.beginPath(); ctx.moveTo(0.5, y0); ctx.lineTo(0.5, y0 + h); stroke(ctx, mix(c.tile, c.light, 0.3), 0.01);
      ctx.beginPath(); ctx.moveTo(-0.05, H * 0.1); ctx.lineTo(1.05, H * 0.1); stroke(ctx, mix(c.light, c.form, 0.3), 0.014);
      ctx.beginPath(); ctx.moveTo(p.pole, H * 0.1); ctx.lineTo(p.pole, H + 0.1); stroke(ctx, mix(c.light, c.form, 0.25), 0.016);
      ctx.restore();
    },
  };

  // A room at evening: a wall, a floor line, a lamp's warm pool.
  G.room = {
    label: 'room', motion: 'the lamp pool breathes',
    build: (r) => ({ lx: r.range(0.2, 0.8), ly: r.range(0.3, 0.5), floor: r.range(0.74, 0.82), pic: r.chance(0.5), px: r.range(0.15, 0.6), warm: r.range(0.12, 0.28) }),
    tone: (c, p) => mix(dark(c, 0.35), c.accent, p.warm * 0.6),
    draw(ctx, p, c, t, still, H) {
      const wall = mix(dark(c, 0.4), c.accent, p.warm);
      ctx.fillStyle = vgrad(ctx, 0, H, [[0, mix(wall, c.deep, 0.25)], [p.floor, wall], [p.floor + 0.001, mix(c.deep, c.form, 0.2)], [1, c.deep]]); ctx.fillRect(0, 0, 1, H);
      glow(ctx, p.lx, p.ly * H, 0.6 * (still ? 1 : 0.95 + 0.05 * BR(t, false)), c.accent, 0.32);
      if (p.pic) { rr(ctx, p.px, H * 0.22, 0.2, H * 0.16, 0.006); stroke(ctx, mix(wall, c.light, 0.25), 0.006, 0.6); }
      ctx.beginPath(); ctx.moveTo(0, p.floor * H); ctx.lineTo(1, p.floor * H); stroke(ctx, mix(wall, c.light, 0.2), 0.004, 0.5);
    },
  };

  // Noise in its own colour: a bright near-white, a soft pink, a deep
  // brown, each leaning a little toward the palette. Build is unchanged, so
  // frozen params (the Stillness preset's) stay valid.
  const NOISE = { white: '#F3F1EC', pink: '#E6B3AA', brown: '#4F3426' };
  const grainOld = G.grain.draw;
  G.grain.tone = (c, p) => { const lean = p.colour === 'white' ? c.tile : p.colour === 'pink' ? c.accent : c.deep, base = mix(NOISE[p.colour] || NOISE.brown, lean, 0.18); return mix(base, (p.tint || 0) > 0 ? '#ffffff' : '#000000', Math.abs(p.tint || 0) * (p.colour === 'white' ? 0.25 : 0.4)); };
  let grainCv = null;
  const grainTex = () => { if (grainCv) return grainCv; const N = 128, cv = document.createElement('canvas'); cv.width = cv.height = N; const g = cv.getContext('2d'), img = g.createImageData(N, N), r = C.makeRng('noise-grain-5'); for (let i = 0; i < img.data.length; i += 4) { const v = r.next() * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; } g.putImageData(img, 0, 0); return (grainCv = cv); };
  G.grain.draw = function (ctx, p, c, t, still, H) {
    const base = G.grain.tone(c, p), coarse = p.colour === 'brown' ? 2.4 : p.colour === 'pink' ? 1.6 : 1, dk = mix(base, '#000000', p.colour === 'white' ? 0.1 : 0.25);
    ctx.fillStyle = vgrad(ctx, 0, H, [[0, mix(base, '#ffffff', p.colour === 'brown' ? 0.04 : 0.08)], [1, dk]]); ctx.fillRect(0, 0, 1, H);
    ctx.save(); ctx.globalCompositeOperation = p.colour === 'white' ? 'multiply' : 'overlay'; ctx.globalAlpha = p.colour === 'white' ? 0.16 : p.colour === 'pink' ? 0.32 : 0.42;
    const pat = C.pattern(ctx, grainTex(), 1, 1); pat.setTransform(new DOMMatrix().translate(still ? 0 : 0.05 * S(t, 30), 0).scale(coarse / 256));
    ctx.fillStyle = pat; ctx.fillRect(0, 0, 1, H); ctx.restore();
    const band = p.colour === 'white' ? mix(base, c.deep, 0.5) : '#ffffff';
    if (p.kind === 'bands') p.bands.forEach((ph, i) => { ctx.fillStyle = css(band, 0.05 + 0.025 * (still ? 0 : S(t, 12 + i * 2, ph))); ctx.fillRect(0, H * (i + 0.5) / p.bands.length, 1, H * 0.035); });
    if (p.kind === 'drift') { ctx.save(); ctx.translate(0.5, H / 2); ctx.rotate(p.ang); ctx.lineCap = 'round'; p.bands.forEach((ph, i) => { const y = ((i + 0.5) / p.bands.length - 0.5) * 1.4 * H; ctx.beginPath(); for (let x = -0.8; x <= 0.8; x += 0.02) ctx.lineTo(x, y + 0.02 * Math.sin(TAU * x * 1.3 + ph + (still ? 0 : TAU * t / 24))); ctx.strokeStyle = css(band, 0.1); ctx.lineWidth = 0.02; ctx.stroke(); }); ctx.restore(); }
  };
  void grainOld;

  // ================= place figures =================

  P.lamp = {
    label: 'lamp', motion: 'its light breathes; a pendant sways a little',
    build: (r, pl) => ({ ...pl, kind: r.pick(['table', 'pendant']), shade: r.range(0.8, 1.1) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), s = p.s;
      if (p.kind === 'table') {
        const top = p.cy - s * 0.55, bot = p.cy + s * 0.75;
        glow(ctx, p.cx, top + s * 0.4, s * 1.8, k.glow, 0.3 + 0.12 * b);
        ctx.beginPath(); ctx.ellipse(p.cx, bot, s * 0.4, s * 0.08, 0, 0, TAU); fill(ctx, k.line);
        ctx.beginPath(); ctx.moveTo(p.cx, bot); ctx.lineTo(p.cx, top + s * 0.4); stroke(ctx, k.line, s * 0.06);
        C.cutPoly(ctx, [[p.cx - s * 0.32 * p.shade, top], [p.cx + s * 0.32 * p.shade, top], [p.cx + s * 0.6 * p.shade, top + s * 0.5], [p.cx - s * 0.6 * p.shade, top + s * 0.5]], C.makeRng('shade'), 0.003); fill(ctx, k.main);
        ctx.beginPath(); ctx.ellipse(p.cx, top + s * 0.5, s * 0.6 * p.shade, s * 0.05, 0, 0, TAU); fill(ctx, k.glow, 0.7 + 0.3 * b);
      } else {
        const a = still ? 0 : 0.035 * S(t, 7.5), top = p.cy - s * 1.3;
        ctx.save(); ctx.translate(p.cx, top); ctx.rotate(a);
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, s * 0.9); stroke(ctx, k.line, s * 0.025);
        const g = ctx.createLinearGradient(0, s * 1.2, 0, s * 2.6); g.addColorStop(0, css(k.glow, 0.35 + 0.15 * b)); g.addColorStop(1, css(k.glow, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(-s * 0.42, s * 1.25); ctx.lineTo(s * 0.42, s * 1.25); ctx.lineTo(s * 1.0, s * 2.6); ctx.lineTo(-s * 1.0, s * 2.6); ctx.closePath(); ctx.fill();
        ctx.beginPath(); ctx.arc(0, s * 1.25, s * 0.45 * p.shade, Math.PI, TAU); ctx.closePath(); fill(ctx, k.main);
        C.circle(ctx, 0, s * 1.28, s * 0.12); fill(ctx, k.glow, 0.85 + 0.15 * b);
        ctx.restore();
      }
    },
  };

  P.window = {
    label: 'window', motion: 'rain runs down it, or a moon glows in it',
    build: (r, pl) => ({ ...pl, view: r.pick(['rain', 'rain', 'moon']), mull: r.pick(['cross', 'vertical']), drops: Array.from({ length: 18 }, () => ({ x: r.next(), y: r.next(), v: r.range(0.05, 0.09) })) }),
    draw(ctx, p, k, t, still) {
      const w = p.s * 1.5, h = p.s * 1.9, x0 = p.cx - w / 2, y0 = p.cy - h / 2;
      glow(ctx, p.cx, p.cy, p.s * 1.6, k.glow, 0.18 + 0.08 * BR(t, still));
      ctx.save(); rr(ctx, x0, y0, w, h, p.s * 0.08); ctx.clip();
      ctx.fillStyle = vgrad(ctx, y0, y0 + h, [[0, mix(k.alt, k.paper, 0.5)], [1, k.alt]]); ctx.fillRect(x0, y0, w, h);
      if (p.view === 'moon') { C.circle(ctx, x0 + w * 0.68, y0 + h * 0.3, p.s * 0.2); fill(ctx, k.glow, 0.9); }
      else for (const d of p.drops) { const u = still ? d.y : (d.y + t * d.v) % 1, x = x0 + d.x * w, y = y0 + u * h; ctx.beginPath(); ctx.moveTo(x, y - 0.03); ctx.lineTo(x, y); stroke(ctx, k.paper, 0.004, 0.7 * fade(u)); }
      ctx.restore();
      rr(ctx, x0, y0, w, h, p.s * 0.08); stroke(ctx, k.main, p.s * 0.1);
      ctx.beginPath(); ctx.moveTo(p.cx, y0); ctx.lineTo(p.cx, y0 + h); if (p.mull === 'cross') { ctx.moveTo(x0, p.cy - h * 0.05); ctx.lineTo(x0 + w, p.cy - h * 0.05); } stroke(ctx, k.main, p.s * 0.06);
      rr(ctx, x0 - p.s * 0.12, y0 + h + p.s * 0.04, w + p.s * 0.24, p.s * 0.1, 0.004); fill(ctx, k.main);
    },
  };

  P.cup = {
    label: 'cup with steam', motion: 'steam curls up and thins away',
    build: (r, pl) => ({ ...pl, wisps: Array.from({ length: 3 }, (_, i) => ({ dx: (i - 1) * 0.22, ph: r.range(0, TAU), per: r.range(5, 8) })), handle: r.sign() }),
    draw(ctx, p, k, t, still) {
      const s = p.s, top = p.cy + s * 0.05, bot = p.cy + s * 0.7, w = s * 0.62;
      ctx.beginPath(); ctx.ellipse(p.cx, bot + s * 0.02, s * 0.95, s * 0.14, 0, 0, TAU); fill(ctx, k.alt);
      ctx.beginPath(); ctx.arc(p.cx + p.handle * w * 0.98, top + s * 0.28, s * 0.2, -Math.PI / 2, Math.PI / 2, p.handle < 0); stroke(ctx, k.main, s * 0.09);
      ctx.beginPath(); ctx.moveTo(p.cx - w, top); ctx.bezierCurveTo(p.cx - w, bot - s * 0.1, p.cx - w * 0.75, bot, p.cx, bot); ctx.bezierCurveTo(p.cx + w * 0.75, bot, p.cx + w, bot - s * 0.1, p.cx + w, top); ctx.closePath(); fill(ctx, k.main);
      ctx.beginPath(); ctx.ellipse(p.cx, top, w, s * 0.1, 0, 0, TAU); fill(ctx, k.line);
      p.wisps.forEach((q) => { ctx.beginPath(); for (let i = 0; i <= 40; i++) { const u = i / 40, y = top - s * 0.15 - u * s * 1.2, x = p.cx + q.dx * s + s * 0.12 * u * Math.sin(TAU * u * 1.2 - (still ? 0 : TAU * t / q.per) + q.ph); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } const g = ctx.createLinearGradient(0, top - s * 0.15, 0, top - s * 1.35); g.addColorStop(0, css(k.line, 0.55)); g.addColorStop(1, css(k.line, 0)); ctx.strokeStyle = g; ctx.lineWidth = s * 0.05; ctx.lineCap = 'round'; ctx.stroke(); });
    },
  };

  P.porthole = {
    label: 'washing-machine porthole', motion: 'the drum turns slowly, the water rocking',
    build: (r, pl) => ({ ...pl, clothes: Array.from({ length: 3 }, () => ({ a: r.range(0, TAU), d: r.range(0.25, 0.55), r: r.range(0.18, 0.3), role: r.pick(['alt', 'glow', 'paper']) })), per: r.range(10, 14) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, R = s * 0.62, cy = p.cy + s * 0.08;
      rr(ctx, p.cx - s * 0.95, p.cy - s * 0.95, s * 1.9, s * 1.95, s * 0.12); fill(ctx, k.main);
      ctx.beginPath(); ctx.moveTo(p.cx - s * 0.95, p.cy - s * 0.62); ctx.lineTo(p.cx + s * 0.95, p.cy - s * 0.62); stroke(ctx, k.line, 0.004, 0.6);
      [0.55, 0.7].forEach((u) => { C.circle(ctx, p.cx + s * u, p.cy - s * 0.78, s * 0.06); fill(ctx, k.line); });
      C.circle(ctx, p.cx, cy, R * 1.18); fill(ctx, k.line);
      ctx.save(); C.circle(ctx, p.cx, cy, R); ctx.clip();
      ctx.fillStyle = css(mix(k.alt, k.paper, 0.4)); ctx.fillRect(p.cx - R, cy - R, R * 2, R * 2);
      const rot = still ? 0 : TAU * t / p.per;
      for (const q of p.clothes) { const a = q.a + rot, x = p.cx + Math.cos(a) * R * q.d, y = cy + Math.sin(a) * R * q.d; ctx.beginPath(); ctx.ellipse(x, y, R * q.r, R * q.r * 0.6, a, 0, TAU); fill(ctx, k[q.role], 0.85); }
      const wl = cy + R * (0.25 + (still ? 0 : 0.06 * S(t, p.per / 2))); ctx.beginPath(); ctx.moveTo(p.cx - R, wl); for (let x = -R; x <= R; x += R / 12) ctx.lineTo(p.cx + x, wl + R * 0.05 * Math.sin(x / R * 5 + (still ? 0 : t))); ctx.lineTo(p.cx + R, cy + R); ctx.lineTo(p.cx - R, cy + R); ctx.closePath(); fill(ctx, k.alt, 0.45);
      C.circle(ctx, p.cx - R * 0.4, cy - R * 0.45, R * 0.18); fill(ctx, '#ffffff', 0.25);
      ctx.restore();
      C.circle(ctx, p.cx, cy, R); stroke(ctx, k.glow, s * 0.05, 0.7);
    },
  };

  P.fan = {
    label: 'fan', motion: 'the blades turn slowly behind the guard',
    build: (r, pl) => ({ ...pl, n: r.pick([3, 4, 5]), per: r.range(6, 9), stand: r.chance(0.6) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, R = s * 0.85, rot = still ? 0.3 : TAU * t / p.per;
      if (p.stand) { ctx.beginPath(); ctx.moveTo(p.cx, p.cy); ctx.lineTo(p.cx, p.cy + s * 1.35); stroke(ctx, k.line, s * 0.07); ctx.beginPath(); ctx.ellipse(p.cx, p.cy + s * 1.38, s * 0.5, s * 0.08, 0, 0, TAU); fill(ctx, k.line); }
      for (let i = 0; i < p.n; i++) { const a = rot + i / p.n * TAU; ctx.beginPath(); ctx.moveTo(p.cx, p.cy); ctx.bezierCurveTo(p.cx + Math.cos(a - 0.5) * R * 0.5, p.cy + Math.sin(a - 0.5) * R * 0.5, p.cx + Math.cos(a - 0.35) * R * 0.95, p.cy + Math.sin(a - 0.35) * R * 0.95, p.cx + Math.cos(a) * R * 0.92, p.cy + Math.sin(a) * R * 0.92); ctx.bezierCurveTo(p.cx + Math.cos(a + 0.25) * R * 0.8, p.cy + Math.sin(a + 0.25) * R * 0.8, p.cx + Math.cos(a + 0.3) * R * 0.3, p.cy + Math.sin(a + 0.3) * R * 0.3, p.cx, p.cy); fill(ctx, k.main, 0.92); }
      C.circle(ctx, p.cx, p.cy, R * 0.16); fill(ctx, k.alt);
      C.circle(ctx, p.cx, p.cy, R * 1.05); stroke(ctx, k.line, s * 0.025, 0.8);
      for (let i = 0; i < 16; i++) { const a = i / 16 * TAU; ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * R * 0.2, p.cy + Math.sin(a) * R * 0.2); ctx.lineTo(p.cx + Math.cos(a) * R * 1.05, p.cy + Math.sin(a) * R * 1.05); stroke(ctx, k.line, 0.002, 0.35); }
      C.circle(ctx, p.cx, p.cy, R * 0.6); stroke(ctx, k.line, 0.002, 0.35);
    },
  };

  P.umbrella = {
    label: 'umbrella', motion: 'sways under the rain; drips fall from the ribs',
    build: (r, pl) => ({ ...pl, ribs: r.int(5, 7), drops: Array.from({ length: 16 }, () => ({ x: r.range(-1.6, 1.6), y: r.next(), v: r.range(0.07, 0.11) })), drips: Array.from({ length: 4 }, () => ({ i: r.next(), y: r.next(), v: r.range(0.05, 0.08) })) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, R = s * 1.05, top = p.cy - s * 0.35, a = still ? 0 : 0.05 * S(t, 8);
      for (const d of p.drops) { const u = still ? d.y : (d.y + t * d.v) % 1, x = p.cx + d.x * s, y = p.cy - s * 1.5 + u * s * 3; if (Math.abs(x - p.cx) < R && y > top - R * 0.5 && y < top + s * 0.1) continue; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 0.004, y + 0.035); stroke(ctx, k.line, 0.003, 0.6 * fade(u)); }
      ctx.save(); ctx.translate(p.cx, top); ctx.rotate(a);
      ctx.beginPath(); ctx.moveTo(0, -R * 0.62); ctx.lineTo(0, s * 1.15); ctx.arc(-s * 0.13, s * 1.15, s * 0.13, 0, Math.PI); stroke(ctx, k.line, s * 0.05);
      ctx.beginPath(); ctx.moveTo(-R, 0); ctx.bezierCurveTo(-R, -R * 0.75, R, -R * 0.75, R, 0);
      for (let i = p.ribs; i > 0; i--) { const x1 = -R + (2 * R) * (i - 1) / p.ribs, x2 = -R + (2 * R) * i / p.ribs; ctx.quadraticCurveTo((x1 + x2) / 2, -R * 0.08, x1, 0); }
      ctx.closePath(); fill(ctx, k.main);
      for (let i = 1; i < p.ribs; i++) { const x = -R + (2 * R) * i / p.ribs; ctx.beginPath(); ctx.moveTo(0, -R * 0.58); ctx.quadraticCurveTo(x * 0.6, -R * 0.45, x, 0); stroke(ctx, k.alt, 0.003, 0.6); }
      for (const q of p.drips) { const u = still ? q.y : (q.y + t * q.v) % 1, x = -R + 2 * R * Math.round(q.i * p.ribs) / p.ribs; C.circle(ctx, x, u * s * 0.9, 0.007); fill(ctx, k.line, fade(u) * 0.8); }
      ctx.restore();
    },
  };

  P.railing = {
    label: 'railing', motion: 'beads gather on the rail and drip',
    build: (r, pl) => ({ ...pl, n: r.int(5, 8), beads: Array.from({ length: 10 }, () => ({ x: r.next(), r: r.range(0.005, 0.01) })), drips: Array.from({ length: 4 }, () => ({ x: r.next(), y: r.next(), v: r.range(0.06, 0.1) })) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, x0 = p.cx - s * 1.3, x1 = p.cx + s * 1.3, y0 = p.cy - s * 0.3, y1 = p.cy + s * 0.8;
      ctx.fillStyle = css(k.main); ctx.fillRect(x0, y0, x1 - x0, s * 0.09); ctx.fillRect(x0, y1, x1 - x0, s * 0.07);
      for (let i = 0; i <= p.n; i++) { const x = lerp(x0 + s * 0.05, x1 - s * 0.05, i / p.n); ctx.fillRect(x - s * 0.025, y0, s * 0.05, y1 - y0); }
      const kk = { light: k.paper, dark: k.line };
      for (const b of p.beads) bead(ctx, lerp(x0, x1, b.x), y0 + s * 0.11, b.r, kk);
      for (const d of p.drips) { const u = still ? d.y : (d.y + t * d.v) % 1, x = lerp(x0, x1, d.x); C.circle(ctx, x, y0 + s * 0.12 + u * s * 1.2, 0.006); fill(ctx, k.line, fade(u) * 0.8); }
    },
  };

  P.droplets = {
    label: 'droplets', motion: 'beads sit; a few slide down, leaving a trail',
    build: (r, pl) => ({ ...pl, beads: Array.from({ length: r.int(24, 36) }, () => ({ x: r.range(-1, 1), y: r.range(-1, 1), r: r.range(0.006, 0.018) })).filter((b) => b.x * b.x + b.y * b.y < 1.1), runs: Array.from({ length: 4 }, () => ({ x: r.range(-0.8, 0.8), y: r.next(), v: r.range(0.03, 0.05) })) }),
    draw(ctx, p, k, t, still) {
      const s = p.s * 1.15, kk = { light: k.paper, dark: k.line };
      for (const b of p.beads) bead(ctx, p.cx + b.x * s, p.cy + b.y * s, b.r * 1.3, { light: k.main, dark: k.line });
      for (const q of p.runs) { const u = still ? q.y : (q.y + t * q.v) % 1, x = p.cx + q.x * s, y = p.cy - s + u * s * 2; ctx.beginPath(); ctx.moveTo(x, y - s * 0.4 * u); ctx.lineTo(x + 0.002, y); stroke(ctx, k.main, 0.004, 0.4 * fade(u)); bead(ctx, x, y, 0.016, { light: k.main, dark: k.line }, fade(u)); }
      void kk;
    },
  };

  P.strap = {
    label: 'handrail straps', motion: 'the straps swing gently with the carriage',
    build: (r, pl) => ({ ...pl, n: r.int(2, 4), kind: r.pick(['ring', 'triangle']), straps: Array.from({ length: 4 }, () => ({ ph: r.range(0, TAU), len: r.range(0.75, 1.05) })) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, bar = p.cy - s * 0.9;
      ctx.beginPath(); ctx.moveTo(p.cx - s * 1.5, bar); ctx.lineTo(p.cx + s * 1.5, bar); stroke(ctx, k.line, s * 0.07);
      for (let i = 0; i < p.n; i++) {
        const q = p.straps[i], x = p.cx + (i - (p.n - 1) / 2) * s * 0.9, a = still ? 0 : 0.09 * S(t, 4.3, q.ph * 0.2), L = s * q.len * 1.1;
        ctx.save(); ctx.translate(x, bar); ctx.rotate(a);
        rr(ctx, -s * 0.07, 0, s * 0.14, L, s * 0.04); fill(ctx, k.main);
        ctx.beginPath(); if (p.kind === 'ring') ctx.arc(0, L + s * 0.2, s * 0.2, 0, TAU); else { ctx.moveTo(0, L - s * 0.02); ctx.lineTo(s * 0.24, L + s * 0.36); ctx.lineTo(-s * 0.24, L + s * 0.36); ctx.closePath(); }
        stroke(ctx, k.alt, s * 0.07); ctx.restore();
      }
    },
  };

  P.doorway = {
    label: 'doorway with light', motion: 'the light inside breathes and spills on the floor',
    build: (r, pl) => ({ ...pl, arch: r.chance(0.4), ajar: r.range(0.2, 0.5) }),
    draw(ctx, p, k, t, still) {
      const s = p.s, b = BR(t, still), w = s * 0.9, h = s * 1.7, x0 = p.cx - w / 2, y0 = p.cy - h / 2, bot = y0 + h;
      const g = ctx.createLinearGradient(0, bot, 0, bot + s * 0.8); g.addColorStop(0, css(k.glow, 0.45 + 0.15 * b)); g.addColorStop(1, css(k.glow, 0)); ctx.fillStyle = g;
      ctx.beginPath(); ctx.moveTo(x0, bot); ctx.lineTo(x0 + w, bot); ctx.lineTo(x0 + w * 1.6, bot + s * 0.8); ctx.lineTo(x0 - w * 0.5, bot + s * 0.8); ctx.closePath(); ctx.fill();
      const door = () => { ctx.beginPath(); ctx.moveTo(x0, bot); if (p.arch) { ctx.lineTo(x0, y0 + w / 2); ctx.arc(p.cx, y0 + w / 2, w / 2, Math.PI, 0); } else { ctx.lineTo(x0, y0); ctx.lineTo(x0 + w, y0); } ctx.lineTo(x0 + w, bot); ctx.closePath(); };
      door(); ctx.fillStyle = vgrad(ctx, y0, bot, [[0, mix(k.glow, k.paper, 0.2)], [1, k.glow]]); ctx.globalAlpha = 0.75 + 0.25 * b; ctx.fill(); ctx.globalAlpha = 1;
      door(); stroke(ctx, k.main, s * 0.08);
      ctx.beginPath(); ctx.moveTo(x0 + w, bot); ctx.lineTo(x0 + w - w * p.ajar, bot - s * 0.06); ctx.lineTo(x0 + w - w * p.ajar, y0 + (p.arch ? w * 0.3 : s * 0.06)); ctx.lineTo(x0 + w, y0 + (p.arch ? w / 2 : 0)); ctx.closePath(); fill(ctx, k.main, 0.9);
    },
  };

  // ================= bells =================
  // A bell is drawn from the five controls of its sound (BellData, read from
  // tools/meditejo/generate_bells.py by bell_params.py), the same five a
  // custom-bell editor would expose:
  //   pitch   -> size and proportions      bright  -> rim, ink and highlight
  //   ring    -> how long the motion lasts strike  -> how hard it is knocked
  //   shimmer -> the rim's oscillation, at the sound's own beat rate.
  // The family (bowl, temple bell, gong...) is the shape. It is still until
  // struck (t = 0 is the preview's start), then moves as it sounds and
  // settles; still draws it at rest.
  const BD = typeof BellData !== 'undefined' ? BellData : {};
  const FAMILY = { swell: 'swell', bowl_small: 'bowl', bowl_medium: 'bowl', bowl_deep: 'bowl', temple: 'temple', handbell: 'hand', chime: 'chime', tingsha: 'tingsha', wood_block: 'block', wooden_fish: 'fish', gong: 'gong' };
  const KNOBS = { pitch: [80, 4000, 'Hz', 'log'], bright: [0, 1, '', 'lin'], ring: [0.03, 8, 's', 'log'], strike: [0, 1, '', 'lin'], shimmer: [0, 8, 'Hz', 'lin'] };
  const clampK = (n, v) => C.clamp(v, KNOBS[n][0], KNOBS[n][1]);
  // How the knobs read on the page. ref is the preset the bell started from,
  // so a shipped bell draws at its family's own size.
  function look(p, k) {
    const kn = p.knobs, ref = (BD[p.preset] && BD[p.preset].knobs) || kn, bv = Math.pow(C.clamp(kn.bright / 0.65, 0, 1), 0.6);
    const L = {
      sc: C.clamp(Math.pow(ref.pitch / kn.pitch, 0.22), 0.72, 1.28),
      V: C.clamp(0.45 + 1.25 * kn.ring, 0.45, 10), amp: 0.3 + 0.7 * kn.strike, hit: lerp(0.6, 0.25, kn.strike), rise: 0.03 + 0.6 * Math.pow(1 - kn.strike, 3),
      rate: Math.min(kn.shimmer, 7), depth: kn.shimmer > 0 ? C.clamp(0.3 + kn.shimmer / 2.5, 0, 1) : 0,
      body: mix(mix(k.main, k.line, 0.45), mix(k.main, k.glow, 0.28), bv), rim: mix(k.alt, k.glow, bv), hi: 0.2 + 0.8 * bv, rw: 0.7 + 0.9 * bv, soft: 1 - kn.strike, bv,
    };
    L.e = (t, still) => (still || t < L.hit ? 0 : (1 - Math.exp(-(t - L.hit) / L.rise)) * Math.exp(-(t - L.hit) / L.V));
    L.sh = (t, still) => (still || !L.depth ? 1 : 1 - L.depth * 0.5 * (1 - Math.cos(TAU * L.rate * Math.max(0, t - L.hit))));
    L.toward = (t, still) => (still || t >= L.hit ? 0 : Math.sin(Math.PI / 2 * (1 - t / L.hit))); // 1 at the back of the swing, 0 at contact
    return L;
  }
  // Sound leaving the instrument: rings open while it rings; more and wider
  // the longer it rings.
  function waves(ctx, x, y, r0, L, k, t, still, sq = 1) {
    if (still || t < L.hit) return;
    const n = Math.round(C.clamp(1 + L.V / 1.5, 1, 5)), span = L.V * 0.9;
    for (let i = 0; i < n; i++) { const u = (t - L.hit) / span - i * 0.22; if (u <= 0 || u >= 1) continue; ctx.beginPath(); ctx.ellipse(x, y, r0 * (1 + u * 1.3), r0 * (1 + u * 1.3) * sq, 0, 0, TAU); stroke(ctx, k.glow, 0.006 * (1 - u) + 0.002, (0.45 + 0.35 * L.bv) * (1 - u) * L.sh(t)); }
  }
  function bellShape(ctx, w, h) { // a classic bell, mouth at y = 0, crown at y = -h
    ctx.beginPath(); ctx.moveTo(-w * 0.58, 0); ctx.bezierCurveTo(-w * 0.45, -h * 0.12, -w * 0.32, -h * 0.4, -w * 0.32, -h * 0.72); ctx.bezierCurveTo(-w * 0.32, -h * 1.02, w * 0.32, -h * 1.02, w * 0.32, -h * 0.72); ctx.bezierCurveTo(w * 0.32, -h * 0.4, w * 0.45, -h * 0.12, w * 0.58, 0); ctx.quadraticCurveTo(0, h * 0.09, -w * 0.58, 0); ctx.closePath();
  }
  // The mallet shows the strike: a soft one has a big felt head, a hard one
  // a small bare tip.
  function mallet(ctx, x, y, a, len, k, soft = 0.5) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(a);
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(len, 0); stroke(ctx, k.line, len * 0.06);
    C.circle(ctx, len, 0, len * (0.07 + 0.12 * soft)); fill(ctx, mix(k.line, k.alt, 0.25 + 0.75 * soft));
    ctx.restore();
  }
  // Brightness as a sheen down the body.
  function sheen(ctx, x, y0, y1, w, L) {
    ctx.beginPath(); ctx.moveTo(x, y0); ctx.quadraticCurveTo(x - w, (y0 + y1) / 2, x, y1); stroke(ctx, '#ffffff', w * 0.9, 0.05 + 0.4 * L.bv);
  }
  // A short glint where the bell is struck, sized by the strike.
  function spark(ctx, x, y, s, L, k, t, still) {
    if (still || t < L.hit) return;
    const u = (t - L.hit) / 0.45; if (u >= 1) return;
    for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + (i - 2) * 0.5, r0 = s * (0.12 + u * 0.25 * L.amp), r1 = r0 + s * 0.16 * L.amp * (1 - u); ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * r0, y + Math.sin(a) * r0); ctx.lineTo(x + Math.cos(a) * r1, y + Math.sin(a) * r1); stroke(ctx, k.glow, 0.004, (1 - u) * (0.4 + 0.6 * L.amp)); }
  }
  P.bell = {
    label: 'bell', motion: 'still until struck; then moves as its sound does, and settles',
    build: (r, pl) => { const preset = pl.preset || r.pick(Object.keys(FAMILY)), d = BD[preset]; return { ...pl, preset, kind: FAMILY[preset], knobs: { ...(d ? d.knobs : { pitch: 400, bright: 0.2, ring: 1.5, strike: 0.5, shimmer: 0.6 }) }, tilt: r.range(-0.06, 0.06) }; },
    draw(ctx, p, k, t, still) {
      const L = look(p, k), kn = p.knobs, cx = p.cx, cy = p.cy, sh = L.sh(t, still), e = L.e(t, still), body = L.body;
      const s = p.kind === 'bowl' || p.kind === 'chime' ? p.s : p.s * L.sc;
      switch (p.kind) {
        case 'swell': { // the app's own bell: its tone swells, so its glow does
          glow(ctx, cx, cy, s * (1.1 + 0.9 * e), k.glow, (0.18 + 0.32 * e) * (0.6 + 0.4 * L.hi));
          ctx.save(); ctx.translate(cx, cy + s * 0.55); ctx.rotate(0.05 * L.amp * e * Math.sin(TAU * t / 2.4));
          bellShape(ctx, s * 1.25, s * 1.2); fill(ctx, body); sheen(ctx, -s * 0.28, -s * 0.85, -s * 0.12, s * 0.1, L);
          ctx.beginPath(); ctx.arc(0, -s * 1.22, s * 0.1, 0, TAU); stroke(ctx, body, s * 0.05);
          ctx.beginPath(); ctx.ellipse(0, 0, s * 0.72, s * 0.08, 0, 0, Math.PI); stroke(ctx, L.rim, s * 0.045 * L.rw, (0.55 + 0.45 * e) * sh);
          ctx.restore();
          waves(ctx, cx, cy, s * 0.9, L, k, t, still);
          break;
        }
        case 'bowl': { // a singing bowl on its cushion: lower bowls are wider and deeper; the rim shimmers at the beat
          const u = C.clamp(Math.log(700 / kn.pitch) / Math.log(700 / 180), -0.25, 1.25), w = s * (0.92 + 0.3 * u), h = s * (0.4 + 0.38 * u), rim = cy - h * 0.35;
          ctx.beginPath(); ctx.ellipse(cx, rim + h + s * 0.06, w * 0.75, s * 0.14, 0, 0, TAU); fill(ctx, k.alt, 0.8);
          ctx.beginPath(); ctx.moveTo(cx - w, rim); ctx.bezierCurveTo(cx - w, rim + h * 0.8, cx - w * 0.55, rim + h, cx, rim + h); ctx.bezierCurveTo(cx + w * 0.55, rim + h, cx + w, rim + h * 0.8, cx + w, rim); ctx.closePath(); fill(ctx, body);
          ctx.beginPath(); ctx.ellipse(cx, rim, w, s * 0.11, 0, 0, TAU); fill(ctx, k.line);
          ctx.beginPath(); ctx.ellipse(cx, rim, w, s * 0.11, 0, 0, TAU); stroke(ctx, L.rim, s * 0.035 * L.rw, (0.45 + 0.55 * e) * sh);
          sheen(ctx, cx - w * 0.55, rim + h * 0.15, rim + h * 0.8, s * 0.12, L);
          if (e > 0.01) { const a = TAU * L.rate * (t - L.hit) + 0.6; ctx.beginPath(); ctx.ellipse(cx, rim, w, s * 0.11, 0, a, a + 1.1); stroke(ctx, '#ffffff', s * 0.04, L.hi * e * sh); }
          spark(ctx, cx + w, rim + h * 0.35, s, L, k, t, still);
          waves(ctx, cx, rim, w * 1.05, L, k, t, still, 0.3);
          mallet(ctx, cx + w * 1.15, rim + h * 1.05, Math.PI - 0.5 - 0.7 * L.amp * L.toward(t, still), s * 0.9, k, L.soft);
          break;
        }
        case 'temple': { // a bonshō, struck by a hung log, sways once
          const a = 0.06 * L.amp * e * Math.sin(TAU * (t - L.hit) / 2.6), top = cy - s * 1.05;
          ctx.beginPath(); ctx.moveTo(cx - s * 1.1, top); ctx.lineTo(cx + s * 1.1, top); stroke(ctx, k.line, s * 0.08);
          ctx.save(); ctx.translate(cx, top); ctx.rotate(a);
          rr(ctx, -s * 0.06, 0, s * 0.12, s * 0.18, s * 0.03); fill(ctx, k.line);
          const W = s * 0.62, Hh = s * 1.75;
          ctx.beginPath(); ctx.moveTo(-W * 0.85, s * 0.18 + W * 0.3); ctx.quadraticCurveTo(-W * 0.85, s * 0.18, 0, s * 0.18); ctx.quadraticCurveTo(W * 0.85, s * 0.18, W * 0.85, s * 0.18 + W * 0.3); ctx.lineTo(W, Hh); ctx.quadraticCurveTo(0, Hh + s * 0.08, -W, Hh); ctx.closePath(); fill(ctx, body); sheen(ctx, -W * 0.55, s * 0.3, Hh * 0.95, s * 0.12, L);
          [0.6, 1.25].forEach((v) => { ctx.beginPath(); ctx.moveTo(-W * 0.92, s * v); ctx.lineTo(W * 0.92, s * v); stroke(ctx, k.line, s * 0.025, 0.7); });
          for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) { C.circle(ctx, -W * 0.45 + i * W * 0.45, s * 0.36 + j * s * 0.08, s * 0.025); fill(ctx, k.line, 0.8); }
          ctx.beginPath(); ctx.moveTo(-W, Hh); ctx.quadraticCurveTo(0, Hh + s * 0.08, W, Hh); stroke(ctx, L.rim, s * 0.04, (0.45 + 0.55 * e) * sh);
          C.circle(ctx, W * 0.42, s * 1.45, s * 0.1); fill(ctx, L.rim);
          ctx.restore();
          const lx = -s * 0.45 * L.amp * L.toward(t, still);
          ctx.beginPath(); ctx.moveTo(cx + s * 0.9 + lx, top); ctx.lineTo(cx + s * 0.9 + lx, cy + s * 0.35); ctx.moveTo(cx + s * 1.45 + lx, top); ctx.lineTo(cx + s * 1.45 + lx, cy + s * 0.35); stroke(ctx, k.line, 0.003, 0.7);
          rr(ctx, cx + s * 0.62 + lx, cy + s * 0.33, s * 0.95, s * 0.14, s * 0.07); fill(ctx, k.alt);
          spark(ctx, cx + s * 0.5, cy + s * 0.4, s, L, k, t, still);
          waves(ctx, cx, cy + s * 0.4, s * 0.8, L, k, t, still);
          break;
        }
        case 'hand': { // a hand bell that sways from its handle; the clapper lags behind
          const a = 0.34 * L.amp * (still ? 0 : t < L.hit ? -0.4 * (1 - L.toward(t, still)) : e * Math.cos(TAU * (t - L.hit) / 1.5)), pivot = cy - s * 1.05;
          ctx.save(); ctx.translate(cx, pivot); ctx.rotate(a);
          rr(ctx, -s * 0.1, -s * 0.1, s * 0.2, s * 0.78, s * 0.09); fill(ctx, k.alt);
          C.circle(ctx, Math.sin(-a * 1.8) * s * 0.25, s * 1.88, s * 0.11); fill(ctx, k.line);
          ctx.save(); ctx.translate(0, s * 1.85); bellShape(ctx, s * 1.25, s * 1.3); fill(ctx, body); sheen(ctx, -s * 0.28, -s * 0.92, -s * 0.12, s * 0.1, L); ctx.beginPath(); ctx.ellipse(0, 0, s * 0.72, s * 0.08, 0, 0, Math.PI); stroke(ctx, L.rim, s * 0.045 * L.rw, (0.55 + 0.45 * e) * sh); ctx.restore();
          ctx.restore();
          waves(ctx, cx, cy + s * 0.6, s * 0.8, L, k, t, still);
          break;
        }
        case 'chime': { // tubes on a bar; a lower pitch hangs longer tubes (a bar's pitch falls with its length squared)
          const bar = cy - s * 1.1, n = 4, lk = C.clamp(Math.sqrt(1568 / kn.pitch), 0.7, 1.35);
          ctx.beginPath(); ctx.moveTo(cx - s * 0.95, bar); ctx.lineTo(cx + s * 0.95, bar); stroke(ctx, k.line, s * 0.08);
          for (let i = 0; i < n; i++) {
            const x = cx + (i - (n - 1) / 2) * s * 0.42, len = Math.min(s * (1.7 - i * 0.22) * lk, s * 2.25), ei = still || t < L.hit + 0.1 * i ? 0 : e * Math.exp(-0.1 * i), a = 0.14 * L.amp * ei * Math.sin(TAU * (t - L.hit) / (1.3 + i * 0.12) + i);
            ctx.save(); ctx.translate(x, bar); ctx.rotate(a);
            ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(0, s * 0.2); stroke(ctx, k.line, 0.003);
            rr(ctx, -s * 0.07, s * 0.2, s * 0.14, len, s * 0.06); fill(ctx, body);
            ctx.beginPath(); ctx.moveTo(-s * 0.03, s * 0.28); ctx.lineTo(-s * 0.03, s * 0.2 + len * 0.9); stroke(ctx, L.rim, s * 0.025 * L.rw, (0.3 + 0.6 * ei) * L.hi * sh + 0.15);
            ctx.restore();
          }
          const sx = cx + s * 0.95, sy = bar + s * 0.75, back = L.toward(t, still);
          C.circle(ctx, sx + s * 0.35 * L.amp * back, sy, s * 0.07); fill(ctx, k.alt);
          break;
        }
        case 'tingsha': { // two small cymbals, face on, hanging from one cord: they swing in, meet edge to edge once, part, and tremble at the beat
          const close = still ? 0 : t < L.hit ? 1 - L.toward(t, still) : Math.max(0, 1 - (t - L.hit) / 0.5), R = s * 0.46, knot = cy - s * 1.05;
          const d = R * (1.2 - 0.2 * close * (0.6 + 0.4 * L.amp)) + (still ? 0 : s * 0.035 * e * Math.sin(TAU * L.rate * (t - L.hit))), y = cy + s * 0.3;
          ctx.beginPath(); ctx.moveTo(cx - d, y); ctx.quadraticCurveTo(cx - d * 0.5, knot + s * 0.1, cx, knot); ctx.quadraticCurveTo(cx + d * 0.5, knot + s * 0.1, cx + d, y); stroke(ctx, k.line, s * 0.035);
          C.circle(ctx, cx, knot, s * 0.06); fill(ctx, k.line);
          [-1, 1].forEach((sd) => { const x = cx + sd * d; C.circle(ctx, x, y, R); fill(ctx, body); C.circle(ctx, x, y, R * 0.36); fill(ctx, k.alt); C.circle(ctx, x, y, R * 0.92); stroke(ctx, L.rim, s * 0.035 * L.rw, (0.45 + 0.55 * e) * sh); ctx.beginPath(); ctx.arc(x, y, R * 0.62, Math.PI * 1.1, Math.PI * 1.45); stroke(ctx, '#ffffff', s * 0.03, 0.15 + 0.5 * L.hi * (0.3 + 0.7 * e) * sh); });
          spark(ctx, cx, y, s, L, k, t, still);
          waves(ctx, cx, y, R * 2.1, L, k, t, still, 0.6);
          break;
        }
        case 'block': case 'fish': { // struck wood: a mallet knocks once
          const knock = L.e(t, still), y = cy + s * 0.15;
          ctx.save(); ctx.translate(cx, y + knock * s * 0.04 * L.amp);
          if (p.kind === 'block') { C.cutPoly(ctx, [[-s * 0.95, -s * 0.38], [s * 0.95, -s * 0.38], [s * 1.02, s * 0.42], [-s * 1.02, s * 0.42]], C.makeRng('block'), 0.004); fill(ctx, body); rr(ctx, -s * 0.7, -s * 0.05, s * 1.4, s * 0.08, s * 0.04); fill(ctx, k.line); ctx.beginPath(); ctx.moveTo(-s * 0.9, -s * 0.3); ctx.lineTo(s * 0.9, -s * 0.3); stroke(ctx, L.rim, 0.004, 0.4 + 0.4 * L.hi); }
          else { ctx.beginPath(); ctx.ellipse(0, s * 0.62, s * 1.0, s * 0.14, 0, 0, TAU); fill(ctx, k.alt, 0.8); ctx.beginPath(); ctx.ellipse(0, 0, s * 0.95, s * 0.68, 0, 0, TAU); fill(ctx, body); ctx.beginPath(); ctx.ellipse(0, s * 0.1, s * 0.7, s * 0.1, 0, 0.15, Math.PI - 0.15); stroke(ctx, k.line, s * 0.09); for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(-s * 0.2 + i * s * 0.25, -s * 0.25, s * 0.14, Math.PI * 1.15, Math.PI * 1.85); stroke(ctx, L.rim, 0.004, 0.4 + 0.4 * L.hi); } C.circle(ctx, -s * 0.62, -s * 0.18, s * 0.05); fill(ctx, k.line); }
          ctx.restore();
          const after = still || t < L.hit ? 0 : Math.min(1, (t - L.hit) / 0.5);
          mallet(ctx, cx + s * 0.85, y - s * 0.95, Math.PI * 0.62 - 0.9 * L.amp * L.toward(t, still) - 0.45 * after, s * 1.05, k, L.soft);
          spark(ctx, cx + s * 0.3, y - s * 0.45, s, L, k, t, still);
          break;
        }
        case 'gong': { // ripples open from the boss across the face, as long as it rings; the upper modes bloom late
          const a = 0.03 * L.amp * e * Math.sin(TAU * (t - L.hit) / 3), R = s * 0.82;
          ctx.beginPath(); ctx.moveTo(cx - s * 1.15, cy + s * 1.25); ctx.lineTo(cx - s * 1.15, cy - s * 1.1); ctx.lineTo(cx + s * 1.15, cy - s * 1.1); ctx.lineTo(cx + s * 1.15, cy + s * 1.25); stroke(ctx, k.line, s * 0.08);
          ctx.save(); ctx.translate(cx, cy - s * 1.1); ctx.rotate(a);
          ctx.beginPath(); ctx.moveTo(-R * 0.5, 0); ctx.lineTo(-R * 0.35, s * 0.32); ctx.moveTo(R * 0.5, 0); ctx.lineTo(R * 0.35, s * 0.32); stroke(ctx, k.line, 0.003);
          const gy = s * 0.32 + R;
          C.circle(ctx, 0, gy, R); fill(ctx, body);
          C.circle(ctx, 0, gy, R * 0.94); stroke(ctx, L.rim, s * 0.035 * L.rw, (0.35 + 0.65 * e) * sh);
          ctx.beginPath(); ctx.arc(0, gy, R * 0.7, Math.PI * 1.05, Math.PI * 1.45); stroke(ctx, '#ffffff', s * 0.08, 0.05 + 0.35 * L.bv);
          C.circle(ctx, 0, gy, R * 0.28); fill(ctx, k.alt);
          if (!still && t > L.hit) { const span = L.V * 0.7; for (let i = 0; i < 5; i++) { const u = (t - L.hit) / span - i * 0.16; if (u > 0 && u < 1) { C.circle(ctx, 0, gy, R * (0.3 + u * 0.62)); stroke(ctx, k.glow, 0.006, (0.4 + 0.5 * L.hi) * (1 - u) * sh); } } }
          ctx.restore();
          spark(ctx, cx, cy - s * 0.78 + R, s, L, k, t, still);
          waves(ctx, cx, cy - s * 0.78 + R, R * 1.05, { ...L, hit: L.hit + 0.4 }, k, t, still);
          mallet(ctx, cx + s * 1.35, cy + s * 1.0, Math.PI + 0.75 + 0.8 * L.amp * L.toward(t, still), s * 0.75, k, L.soft);
          break;
        }
      }
    },
  };
  // The bells that ship (cueBellSounds in lib/models/cues/cue_settings.dart),
  // each a preset of the five controls.
  P.bell.SHIPPED = [
    ['bell-swell', 'Swell bell', 'session_bell_v2', 'swell'], ['bell-bowl-small', 'Singing bowl, small', 'bell_bowl_small', 'bowl_small'],
    ['bell-bowl-medium', 'Singing bowl', 'bell_bowl_medium', 'bowl_medium'], ['bell-bowl-deep', 'Singing bowl, deep', 'bell_bowl_deep', 'bowl_deep'],
    ['bell-temple', 'Temple bell', 'bell_temple', 'temple'], ['bell-handbell', 'Hand bell', 'bell_handbell', 'handbell'],
    ['bell-chime', 'Chime', 'bell_chime', 'chime'], ['bell-tingsha', 'Tingsha', 'bell_tingsha', 'tingsha'],
    ['bell-wood-block', 'Wood block', 'bell_wood_block', 'wood_block'], ['bell-wooden-fish', 'Wooden fish', 'bell_wooden_fish', 'wooden_fish'],
    ['bell-gong', 'Gong', 'bell_gong', 'gong'],
  ].map(([id, title, file, preset]) => ({ id, title, asset: `assets/audio/${file}.wav`, preset, kind: FAMILY[preset] }));
  P.bell.presetFor = (id) => (P.bell.SHIPPED.find((b) => b.id === id) || {}).preset;
  P.bell.FAMILY = FAMILY; P.bell.KNOBS = KNOBS; P.bell.clampKnob = clampK;
})();
