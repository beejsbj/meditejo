/* Round 4 grounds: round 2's atmospheres rebuilt as grounds that figures sit
 * on. Each fills the whole card (unit wide, H tall), moves slowly and loops
 * without a seam (sines, or phases that wrap off-canvas), and reports its
 * tone so the composition can choose inks that read on it.
 *
 *   { label, motion, build(rng, opts), tone(c, p), draw(ctx, p, c, t, still, H) }
 * c is the palette's roles (Core.roles). */
const Grounds = (() => {
  'use strict';
  const C = Core, { TAU, lerp, css, mix } = C;
  const S = (t, period, ph = 0) => Math.sin(TAU * t / period + ph); // a slow, seamless sine
  const vgrad = (ctx, H, stops) => { const g = ctx.createLinearGradient(0, 0, 0, H); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); ctx.fillStyle = g; ctx.fillRect(0, 0, 1, H); };
  const glow = (ctx, x, y, r, col, a) => { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(0.5, css(col, a * 0.35)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); };
  const dark = (c, k) => mix(c.deep, c.form, k);
  const G = {};

  // Flat paper in one of three value keys: the quietest ground.
  G.paper = {
    label: 'paper', motion: 'none: the figure carries the motion',
    build: (r, o) => ({ key: o.key || r.pick(['light', 'light', 'mid']), k: r.range(0, 0.12) }),
    tone: (c, p) => (p.key === 'light' ? mix(c.tile, c.accent, p.k) : p.key === 'mid' ? mix(c.form, c.tile, 0.35) : dark(c, 0.2)),
    draw(ctx, p, c, t, still, H) { const b = G.paper.tone(c, p); vgrad(ctx, H, [[0, b], [1, mix(b, c.deep, 0.06)]]); },
  };

  // Ridges in mist under a soft light; mist pools above each ridge.
  G.mist = {
    label: 'mist', motion: 'ridges drift apart and back, the light breathes',
    build: (r) => ({ sun: r.chance(0.6), sx: r.range(0.25, 0.75), sy: r.range(0.22, 0.38), layers: Array.from({ length: r.int(2, 3) }, (_, i) => ({ y: lerp(0.62, 0.86, i / 2) + r.range(-0.02, 0.02), amp: r.range(0.02, 0.045), f: r.range(0.6, 1.3), ph: r.range(0, TAU), per: r.range(34, 48) })) }),
    tone: (c) => mix(c.tile, c.form, 0.3),
    draw(ctx, p, c, t, still, H) {
      vgrad(ctx, H, [[0, mix(c.tile, c.form, 0.18)], [0.65, mix(c.tile, c.accent, 0.12)], [1, mix(c.form, c.tile, 0.4)]]);
      if (p.sun) glow(ctx, p.sx, p.sy * H, 0.42, c.accent, 0.28 + (still ? 0 : 0.06 * S(t, 10)));
      const n = p.layers.length;
      p.layers.forEach((L, i) => {
        const k = (i + 1) / n, drift = still ? 0 : 0.03 * S(t, L.per, L.ph), base = L.y * H;
        const mg = ctx.createLinearGradient(0, base - 0.12, 0, base); mg.addColorStop(0, css(c.tile, 0)); mg.addColorStop(1, css(c.tile, 0.45)); ctx.fillStyle = mg; ctx.fillRect(0, base - 0.12, 1, 0.12);
        ctx.beginPath(); ctx.moveTo(-0.1, H + 0.1);
        for (let x = -0.1; x <= 1.1001; x += 0.02) ctx.lineTo(x, base - L.amp * (0.6 + 0.4 * Math.sin(TAU * L.f * (x + drift) + L.ph)));
        ctx.lineTo(1.1, H + 0.1); ctx.closePath(); ctx.fillStyle = css(mix(mix(c.form, c.tile, 0.55 * (1 - k)), c.deep, 0.3 * k * k), 0.9); ctx.fill();
      });
    },
  };

  // A low sun over water, its glow breathing, reflections shimmering.
  G.dawn = {
    label: 'dawn', motion: 'the glow swells on the breath; reflections shimmer',
    build: (r) => ({ h: r.range(0.6, 0.7), sx: r.range(0.3, 0.7), warm: r.range(0.3, 0.55), bars: Array.from({ length: 5 }, () => r.range(0, TAU)) }),
    tone: (c, p) => mix(c.tile, c.accent, p.warm * 0.5),
    draw(ctx, p, c, t, still, H) {
      const h = p.h * H, b = still ? 0.5 : 0.5 + 0.5 * S(t, 10);
      vgrad(ctx, H, [[0, mix(c.tile, c.form, 0.2)], [p.h * 0.95, mix(c.tile, c.accent, p.warm)], [p.h, mix(c.form, c.deep, 0.25)], [1, mix(c.form, c.deep, 0.5)]]);
      glow(ctx, p.sx, h, 0.5 * (0.92 + 0.08 * b), c.accent, 0.42);
      ctx.lineCap = 'round';
      p.bars.forEach((ph, i) => { const y = h + 0.03 + i * 0.045 * H, w = 0.3 * (1 - i * 0.15) * (1 + (still ? 0 : 0.18 * S(t, 7 + i, ph))); ctx.strokeStyle = css(mix(c.accent, c.tile, 0.3), 0.55 - i * 0.08); ctx.lineWidth = 0.008; ctx.beginPath(); ctx.moveTo(p.sx - w / 2, y); ctx.lineTo(p.sx + w / 2, y); ctx.stroke(); });
    },
  };

  // A dim field with soft rain falling through it and one warm lamp.
  G.rainfield = {
    label: 'rain field', motion: 'soft rain falls; the lamp glows on the breath',
    build: (r) => ({ lx: r.range(0.2, 0.8), ly: r.range(0.2, 0.5), drops: Array.from({ length: 60 }, () => ({ x: r.range(-0.1, 1.1), y: r.next(), l: r.range(0.05, 0.11), v: r.range(0.05, 0.09), a: r.range(0.12, 0.35) })), slant: r.range(-0.15, 0) }),
    tone: (c) => mix(c.deep, c.tile, 0.22),
    draw(ctx, p, c, t, still, H) {
      const g = mix(c.deep, c.tile, 0.2);
      vgrad(ctx, H, [[0, mix(g, c.form, 0.25)], [1, mix(c.deep, c.form, 0.12)]]);
      glow(ctx, p.lx, p.ly * H, 0.45, c.accent, 0.2 + (still ? 0 : 0.05 * S(t, 10)));
      ctx.lineCap = 'round'; ctx.lineWidth = 0.003;
      for (const d of p.drops) { const y = ((d.y + (still ? 0 : t * d.v)) % 1.2 - 0.1) * H, x = d.x + y * p.slant; ctx.strokeStyle = css(c.light, d.a); ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d.l * p.slant, y + d.l * H); ctx.stroke(); }
    },
  };

  // Layered crowns of trees under a pale sky, swaying a little.
  G.canopy = {
    label: 'canopy', motion: 'crowns sway, out of step',
    build: (r) => ({ sky: r.pick(['day', 'dawn', 'dusk']), rows: Array.from({ length: 3 }, (_, i) => Array.from({ length: 9 }, (_, j) => ({ x: j / 8 + r.range(-0.05, 0.05), r: r.range(0.08, 0.14) * (1 + i * 0.22), dy: r.range(-0.03, 0.03), ph: r.range(0, TAU) }))) }),
    tone: (c, p) => (p.sky === 'dusk' ? mix(c.accent, c.deep, 0.4) : mix(c.tile, c.form, 0.3)),
    draw(ctx, p, c, t, still, H) {
      const sky = p.sky === 'dawn' ? mix(c.tile, c.accent, 0.35) : p.sky === 'dusk' ? mix(c.accent, c.deep, 0.45) : mix(c.tile, c.form, 0.25);
      vgrad(ctx, H, [[0, mix(sky, c.deep, 0.08)], [0.6, sky], [1, dark(c, 0.4)]]);
      if (p.sky !== 'day') glow(ctx, 0.5, 0.6 * H, 0.5, c.accent, 0.3);
      p.rows.forEach((row, i) => {
        const k = (i + 1) / 3, base = H * (0.66 + i * 0.12);
        ctx.beginPath(); ctx.moveTo(-0.1, H + 0.1);
        row.forEach((cr) => ctx.arc(cr.x + (still ? 0 : 0.006 * S(t, 9 + i * 2, cr.ph)), base + cr.dy * H, cr.r * 0.62, Math.PI, 0));
        ctx.lineTo(1.1, H + 0.1); ctx.closePath(); ctx.fillStyle = css(mix(mix(c.form, c.tile, 0.3 * (1 - k)), c.deep, 0.5 * k)); ctx.fill();
      });
    },
  };

  // A deep field: dust of faint stars, a moon's glow, an optional skyline.
  G.night = {
    label: 'night field', motion: 'faint stars brighten and fade slowly',
    build: (r) => ({ dust: Array.from({ length: 70 }, () => ({ x: r.next(), y: r.next() * 0.8, z: r.range(0.0015, 0.004), ph: r.range(0, TAU), per: r.range(6, 14) })), mx: r.range(0.2, 0.8), moon: r.chance(0.5), land: r.chance(0.5), lp: r.range(0, TAU) }),
    tone: (c) => mix(c.deep, c.form, 0.15),
    draw(ctx, p, c, t, still, H) {
      vgrad(ctx, H, [[0, mix(c.deep, c.tile, 0.02)], [0.8, mix(c.deep, c.form, 0.25)], [1, c.deep]]);
      if (p.moon) glow(ctx, p.mx, 0.22 * H, 0.32, c.light, 0.12);
      for (const d of p.dust) { const a = still ? 0.6 : 0.45 + 0.4 * S(t, d.per, d.ph); C.circle(ctx, d.x, d.y * H, d.z); ctx.fillStyle = css(c.light, a * 0.8); ctx.fill(); }
      if (p.land) { ctx.beginPath(); ctx.moveTo(0, H); for (let x = 0; x <= 1.001; x += 0.02) ctx.lineTo(x, H * (0.88 + 0.025 * Math.sin(x * 7 + p.lp))); ctx.lineTo(1, H); ctx.closePath(); ctx.fillStyle = css(c.deep, 0.95); ctx.fill(); }
    },
  };

  // A banked hearth: warm dark with a low glow that rises and falls.
  G.hearth = {
    label: 'hearth glow', motion: 'the glow rises and settles on two slow clocks',
    build: (r) => ({ x: r.range(0.4, 0.6), w: r.range(0.45, 0.6) }),
    tone: (c) => mix(c.deep, c.form, 0.2),
    draw(ctx, p, c, t, still, H) {
      vgrad(ctx, H, [[0, mix(c.deep, c.tile, 0.03)], [1, dark(c, 0.3)]]);
      const f = still ? 0.5 : 0.5 + 0.3 * S(t, 5.3) + 0.2 * S(t, 8.1, 1);
      glow(ctx, p.x, H * 0.95, p.w * (0.9 + 0.15 * f), c.accent, 0.38 + 0.12 * f);
    },
  };

  // Open sea: a pale sky, a horizon, swells rolling in.
  G.sea = {
    label: 'sea', motion: 'swells roll in, one after another',
    build: (r) => ({ hy: r.range(0.36, 0.46), gx: r.range(0.25, 0.75), rows: r.int(4, 6), ph: r.range(0, TAU) }),
    tone: (c) => mix(c.form, c.deep, 0.3),
    draw(ctx, p, c, t, still, H) {
      const hy = p.hy * H;
      vgrad(ctx, H, [[0, mix(c.form, c.tile, 0.5)], [p.hy, mix(c.tile, c.accent, 0.4)], [p.hy + 0.002, mix(c.form, c.deep, 0.25)], [1, mix(c.form, c.deep, 0.55)]]);
      glow(ctx, p.gx, hy, 0.4, c.accent, 0.35);
      for (let i = 0; i < p.rows; i++) {
        const k = i / (p.rows - 1), y0 = hy + (0.04 + Math.pow(k, 1.3) * (H - hy - 0.04)), amp = (0.003 + 0.016 * k) * H, ph = (still ? 0 : TAU * t / (14 - i)) + i * 1.3 + p.ph;
        ctx.beginPath(); ctx.moveTo(-0.05, H + 0.1);
        for (let x = -0.05; x <= 1.05; x += 0.02) ctx.lineTo(x, y0 + amp * Math.sin(TAU * x * (1.2 + i * 0.25) + ph));
        ctx.lineTo(1.05, H + 0.1); ctx.closePath(); ctx.fillStyle = css(mix(mix(c.form, c.deep, 0.3), c.deep, k * 0.35), 0.5); ctx.fill();
        ctx.strokeStyle = css(c.light, 0.3 - 0.18 * k); ctx.lineWidth = 0.004; ctx.stroke();
      }
    },
  };

  // A warm room seen out of focus: soft discs drifting.
  G.bokeh = {
    label: 'room bokeh', motion: 'lights drift and breathe',
    build: (r) => ({ b: Array.from({ length: 12 }, () => ({ x: r.next(), y: r.range(0.1, 0.9), r: r.range(0.04, 0.12), ph: r.range(0, TAU), per: r.range(14, 24), role: r.pick(['accent', 'accent', 'light', 'form']), a: r.range(0.2, 0.45) })) }),
    tone: (c) => mix(dark(c, 0.3), c.accent, 0.12),
    draw(ctx, p, c, t, still, H) {
      vgrad(ctx, H, [[0, mix(dark(c, 0.3), c.accent, 0.14)], [1, dark(c, 0.15)]]);
      for (const q of p.b) { const x = q.x + (still ? 0 : 0.025 * S(t, q.per, q.ph)), y = q.y * H + (still ? 0 : 0.012 * S(t, q.per * 1.3, q.ph)); glow(ctx, x, y, q.r, c[q.role], q.a * (still ? 1 : 0.85 + 0.15 * S(t, 10, q.ph))); }
    },
  };

  // A tinted texture for the noise colours: fine and bright, mid, coarse
  // and warm. It drifts rather than flickers.
  let grainCv = null;
  const grainTex = () => { if (grainCv) return grainCv; const N = 128, cv = document.createElement('canvas'); cv.width = cv.height = N; const g = cv.getContext('2d'), img = g.createImageData(N, N), r = C.makeRng('noise-grain'); for (let i = 0; i < img.data.length; i += 4) { const v = r.next() * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; } g.putImageData(img, 0, 0); return (grainCv = cv); };
  G.grain = {
    label: 'texture', motion: 'the grain drifts slowly sideways',
    build: (r, o) => ({ colour: o.colour || r.pick(['white', 'pink', 'brown']), kind: r.pick(['even', 'bands', 'drift']), tint: r.range(-0.12, 0.12), bands: Array.from({ length: r.int(5, 9) }, () => r.range(0, TAU)), ang: r.range(-0.5, 0.5) }),
    tone: (c, p) => (p.colour === 'white' ? mix(c.tile, c.form, 0.15 + (p.tint || 0)) : p.colour === 'pink' ? mix(c.form, c.accent, 0.4 + (p.tint || 0)) : dark(c, 0.5 + (p.tint || 0))),
    draw(ctx, p, c, t, still, H) {
      const base = G.grain.tone(c, p), coarse = p.colour === 'brown' ? 2.2 : p.colour === 'pink' ? 1.5 : 1;
      vgrad(ctx, H, [[0, base], [1, mix(base, c.deep, 0.25)]]);
      ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = p.colour === 'white' ? 0.4 : 0.3;
      const pat = C.pattern(ctx, grainTex(), 1, 1); pat.setTransform(new DOMMatrix().translate(still ? 0 : 0.05 * S(t, 30), 0).scale(coarse / 256));
      ctx.fillStyle = pat; ctx.fillRect(0, 0, 1, H); ctx.restore();
      if (p.kind === 'bands') p.bands.forEach((ph, i) => { ctx.fillStyle = css(c.light, 0.05 + 0.03 * (still ? 0 : S(t, 12 + i * 2, ph))); ctx.fillRect(0, H * (i + 0.5) / p.bands.length, 1, H * 0.035); });
      if (p.kind === 'drift') { ctx.save(); ctx.translate(0.5, H / 2); ctx.rotate(p.ang); ctx.lineCap = 'round'; p.bands.forEach((ph, i) => { const y = ((i + 0.5) / p.bands.length - 0.5) * 1.4 * H; ctx.beginPath(); for (let x = -0.8; x <= 0.8; x += 0.02) ctx.lineTo(x, y + 0.02 * Math.sin(TAU * x * 1.3 + ph + (still ? 0 : TAU * t / 24))); ctx.strokeStyle = css(c.light, 0.12); ctx.lineWidth = 0.02; ctx.stroke(); }); ctx.restore(); }
    },
  };

  return G;
})();
