/* Practice figures, round 3: the Headless Way again, and the six round 1
 * figures flagged in round 2 (Caṅkama · Kinhin, Forgiveness, The Mind
 * Illuminated, Anussati, Karuṇā, Jhāna).
 *
 * Burooj on round 2 (2026-11-02): same rules. Abstract, quiet, graceful on
 * a slow ~10 s breath, true to the practice, no human shapes. For the
 * Headless Way: quieter than face to no-face — here, no head: open
 * capacity, full of the world.
 *
 * Same contract and helpers as figures-r2.js (copied, so each file stands
 * alone for porting):
 *   { label, says, build(r, place), draw(ctx, p, k, t, still) }
 * No canvas filters; no hard switches (inks change by mix on a smoothstep). */
const PracticesR3 = (() => {
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

  const tear = (ctx, x, y, h, w) => { ctx.beginPath(); ctx.moveTo(x, y - h); ctx.bezierCurveTo(x + w * 0.9, y - h * 0.35, x + w, y + h * 0.2, x, y + h * 0.3); ctx.bezierCurveTo(x - w, y + h * 0.2, x - w * 0.9, y - h * 0.35, x, y - h); };
  function petal(ctx, x, y, len, wid, ang) {
    const c = Math.cos(ang), s = Math.sin(ang), P = (u, v) => [x + u * c - v * s, y + u * s + v * c];
    const [ax, ay] = P(len, 0), [l1x, l1y] = P(len * 0.35, wid), [l2x, l2y] = P(len * 0.8, wid * 0.6), [r1x, r1y] = P(len * 0.35, -wid), [r2x, r2y] = P(len * 0.8, -wid * 0.6);
    ctx.beginPath(); ctx.moveTo(x, y); ctx.bezierCurveTo(l1x, l1y, l2x, l2y, ax, ay); ctx.bezierCurveTo(r2x, r2y, r1x, r1y, x, y); ctx.closePath();
  }
  const easeIn = (u) => u * u;
  const mod = (x, m) => ((x % m) + m) % m;

  // ================= Headless Way =================
  // Capacity: one clear space with no edge, and the world in it — sky, a
  // passing cloud, a sun, hills, near ground. Nothing else; it breathes.
  F.headless_capacity = {
    label: 'capacity', says: 'The Headless Way: here, no head — a clear space without an edge, full of the world.',
    build: (r, pl) => ({ ...pl, ph: r.next(), hp: r.range(0, TAU) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), x = p.cx, y = p.cy - p.s * 0.05, R = p.s * 0.8 * (0.97 + 0.03 * b);
      const clear = isLight(k) ? mix(k.paper, '#FFFFFF', 0.62) : mix(k.paper, k.main, 0.14);
      const g = ctx.createRadialGradient(x, y, 0, x, y, R * 1.14); g.addColorStop(0, css(clear, 0.96)); g.addColorStop(0.78, css(clear, 0.92)); g.addColorStop(1, css(clear, 0));
      ctx.fillStyle = g; dot(ctx, x, y, R * 1.14); ctx.fill();
      ctx.save(); dot(ctx, x, y, R * 1.02); ctx.clip();
      const hy = y + R * 0.2, u = still ? p.ph : frac(t / (4 * B) + p.ph);
      soft(ctx, x - R * 0.32, hy - R * 0.36, R * 0.5, k.glow, 0.5);
      dot(ctx, x - R * 0.32, hy - R * (0.36 + 0.04 * b), R * 0.1); fill(ctx, k.alt);
      cloud(ctx, x + R * lerp(-1.7, 1.7, u), y - R * 0.5, R * 0.42, mix(clear, k.main, 0.16), 0.85 * fade(u), PUFFS.slice(0, 5));
      ctx.beginPath(); ctx.moveTo(x - R * 1.1, hy + R);
      for (let i = 0; i <= 40; i++) { const v = i / 40; ctx.lineTo(x + R * lerp(-1.1, 1.1, v), hy - R * 0.16 * Math.pow(Math.sin(Math.PI * v * 1.4 + p.hp), 2)); }
      ctx.lineTo(x + R * 1.1, hy + R); ctx.closePath(); fill(ctx, k.line, 0.32);
      ctx.beginPath(); ctx.moveTo(x - R * 1.1, y + R * 1.1);
      for (let i = 0; i <= 40; i++) { const v = i / 40; ctx.lineTo(x + R * lerp(-1.1, 1.1, v), hy + R * (0.22 + 0.05 * Math.sin(TAU * v * 1.2 + p.hp))); }
      ctx.lineTo(x + R * 1.1, y + R * 1.1); ctx.closePath(); fill(ctx, k.main, 0.4);
      ctx.restore();
    },
  };

  // An open ring that is nothing of its own. The sun crosses the sky; while
  // it passes through, the ring is full of its light; then empty again.
  F.headless_passing = {
    label: 'full of what passes', says: 'The Headless Way: an open space with nothing of its own, filled by whatever is there.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const v = still ? 0.47 : frac(t / (3 * B)), th = Math.PI * (1 - v), hy = p.cy + p.s * 0.6, sx = p.cx + p.s * 1.3 * Math.cos(th), sy = hy - p.s * 1.12 * Math.sin(th), a = Math.pow(fade(v), 0.5);
      const rx = p.cx, ry = p.cy - p.s * 0.3, R = p.s * 0.46, inside = (1 - C.ss(R * 0.6, R * 1.15, Math.hypot(sx - rx, sy - ry))) * a;
      ctx.save(); dot(ctx, rx, ry, R); ctx.clip(); soft(ctx, sx, sy, R * 1.8, k.glow, 0.75 * inside); ctx.restore();
      ring(ctx, rx, ry, R); stroke(ctx, k.main, 0.005, 0.35 + 0.35 * inside);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.3, hy); ctx.lineTo(p.cx + p.s * 1.3, hy); stroke(ctx, k.main, 0.005, 0.45);
      soft(ctx, sx, sy, p.s * 0.3, k.glow, 0.5 * a); dot(ctx, sx, sy, p.s * 0.08); fill(ctx, k.alt, a);
    },
  };

  // Harding's tube: at the far end, a face; at this end, no end at all —
  // the tube opens out past every edge.
  F.headless_tube = {
    label: 'the tube', says: 'The Headless Way: at the far end of the tube a face; at this end, no edge — open space.',
    build: (r, pl) => ({ ...pl, n: 7 }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      for (let i = 0; i < 8; i++) { const a = TAU * (i + 0.5) / 8; ctx.beginPath(); ctx.moveTo(p.cx + Math.cos(a) * p.s * 0.18, p.cy + Math.sin(a) * p.s * 0.18); ctx.lineTo(p.cx + Math.cos(a) * p.s * 2, p.cy + Math.sin(a) * p.s * 2); stroke(ctx, k.main, 0.003, 0.14); }
      for (let i = 0; i < p.n; i++) {
        const u = still ? (i + 0.5) / p.n : frac(t / (2 * B) + i / p.n), r = p.s * 0.17 * Math.exp(3.1 * u);
        ring(ctx, p.cx, p.cy, r); stroke(ctx, k.main, 0.003 + 0.012 * u, 0.6 * C.ss(0, 0.15, u) * (1 - C.ss(0.5, 0.92, u)));
      }
      soft(ctx, p.cx, p.cy, p.s * 0.35, k.glow, 0.45 + 0.1 * b);
      dot(ctx, p.cx, p.cy, p.s * 0.1); fill(ctx, k.alt);
    },
  };

  // ================= Caṅkama · Kinhin =================
  // A path, walked back and forth: a light lifts, moves and places, step by
  // step; each step leaves a mark that fades; at the end it pauses, turns.
  F.walk_path = {
    label: 'back and forth', says: 'Caṅkama: walking a path back and forth — lifting, moving, placing — turning at each end.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const N = 8, ST = 2.5, T = 2 * (N + 1) * ST, x0 = p.cx - p.s * 1.0, x1 = p.cx + p.s * 1.0, py = p.cy + p.s * 0.35;
      const at = (tt) => { const tau = mod(tt, T), leg = tau < T / 2 ? 0 : 1, tl = tau - leg * T / 2, kk = Math.floor(tl / ST), f = tl / ST - kk; const walking = kk < N, d = walking ? (kk + C.easeInOut(f)) / N : 1; return { x: leg ? lerp(x1, x0, d) : lerp(x0, x1, d), lift: walking ? Math.sin(Math.PI * f) : 0, turn: walking ? -1 : f, f }; };
      const tt = still ? ST * 3.45 : t, now = at(tt);
      ctx.beginPath(); ctx.moveTo(x0 - p.s * 0.1, py); ctx.lineTo(x1 + p.s * 0.1, py); stroke(ctx, k.main, 0.006, 0.35);
      for (let m = 0; m < 6; m++) { const te = (Math.floor(tt / ST) - m) * ST, q = at(te), age = tt - te; if (at(te - 0.01).turn >= 0 && q.turn < 0 && m > 0) continue; pill(ctx, q.x, py, p.s * 0.1, p.s * 0.035, 0); fill(ctx, k.main, 0.7 * C.ss(0, 0.4, age) * Math.max(0, 1 - age / 12)); }
      if (now.turn < 0 && now.f < 0.35) { ring(ctx, at(Math.floor(tt / ST) * ST).x, py, p.s * (0.05 + 0.3 * now.f / 0.35)); stroke(ctx, k.alt, 0.005, 0.6 * (1 - now.f / 0.35)); }
      if (now.turn >= 0) { ring(ctx, now.x, py - p.s * 0.06, p.s * (0.12 + 0.08 * fade(now.turn))); stroke(ctx, k.glow, 0.006, 0.6 * fade(now.turn)); }
      const wy = py - p.s * (0.06 + 0.14 * now.lift);
      soft(ctx, now.x, wy, p.s * 0.3, k.glow, 0.55); dot(ctx, now.x, wy, p.s * 0.065); fill(ctx, k.alt);
    },
  };

  // Kinhin's half step to a breath: each step drawn as one slow arc —
  // lifting, moving, placing — the trail of earlier steps drifting behind.
  F.walk_arcs = {
    label: 'one step, then the next', says: 'Kinhin: one slow step to each half breath — lifting, moving, placing — then the next.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const ST = B / 2, L = p.s * 0.52, H = p.s * 0.34, base = p.cy + p.s * 0.32, tt = still ? ST * 6.62 : t, c = Math.floor(tt / ST), f = tt / ST - c;
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.3, base); ctx.lineTo(p.cx + p.s * 1.3, base); stroke(ctx, k.main, 0.004, 0.25);
      for (let j = c - 7; j <= c; j++) {
        const sx = p.cx + (j - tt / ST) * L, prog = j < c ? 1 : C.easeInOut(f), edge = C.ss(p.cx - p.s * 1.45, p.cx - p.s * 0.9, sx + L * 0.5), a = (j === c ? 1 : 0.85 * (1 - (c - j) / 8)) * edge;
        ctx.beginPath(); for (let i = 0; i <= 30; i++) { const v = prog * i / 30; const x = sx + v * L, y = base - H * Math.sin(Math.PI * v); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
        stroke(ctx, mix(k.main, k.alt, 1 - C.ss(1, 1.8, tt / ST - j)), 0.014, a);
        if (j < c) { dot(ctx, sx + L, base, p.s * 0.03); fill(ctx, k.main, a); }
      }
      const sx = p.cx - f * L, v = C.easeInOut(f), tx = sx + v * L, ty = base - H * Math.sin(Math.PI * v);
      if (f < 0.3) { ring(ctx, sx, base, p.s * (0.04 + 0.22 * f / 0.3)); stroke(ctx, k.alt, 0.005, 0.6 * (1 - f / 0.3)); }
      soft(ctx, tx, ty, p.s * 0.3, k.glow, 0.6); dot(ctx, tx, ty, p.s * 0.065); fill(ctx, k.alt);
    },
  };

  // Stepping stones going away across still water: a light steps from one
  // to the next, each placing a small ring on the water.
  F.walk_stones = {
    label: 'stepping stones', says: 'Walking: one stone, then the next — each step placed fully before the next is lifted.',
    build: (r, pl) => ({ ...pl, st: Array.from({ length: 6 }, (_, i) => { const z = i / 5, sc = lerp(1, 0.38, z); return { x: (i % 2 ? 1 : -1) * 0.2 * sc + r.range(-0.04, 0.04), y: lerp(0.85, -0.7, Math.pow(z, 0.85)), sc }; }) }),
    draw(ctx, p, k, t, still) {
      const ST = 4, tt = still ? ST * 2.55 : t, c = mod(Math.floor(tt / ST), 7), f = tt / ST - Math.floor(tt / ST);
      const P = (i) => { const s = p.st[i]; return [p.cx + s.x * p.s, p.cy + s.y * p.s, s.sc]; };
      p.st.forEach((s, i) => { const [x, y, sc] = P(i); ctx.beginPath(); ctx.ellipse(x, y, p.s * 0.27 * sc, p.s * 0.085 * sc, 0, 0, TAU); fill(ctx, k.main, 0.32); stroke(ctx, k.main, 0.004, 0.45); });
      let x, y, sc, a = 1, lift = 0;
      if (c < 5) { const [ax, ay, as] = P(c), [bx, by, bs] = P(c + 1), v = C.easeInOut(f); x = lerp(ax, bx, v); y = lerp(ay, by, v); sc = lerp(as, bs, v); lift = Math.sin(Math.PI * f); }
      else if (c === 5) { [x, y, sc] = P(5); a = 1 - C.ss(0.2, 1, f); }
      else { [x, y, sc] = P(0); a = C.ss(0, 0.8, f); }
      if (c < 5 && f < 0.3 && c > 0) { const [lx, ly, ls] = P(c); ctx.beginPath(); ctx.ellipse(lx, ly, p.s * (0.3 + 0.35 * f / 0.3) * ls, p.s * (0.1 + 0.12 * f / 0.3) * ls, 0, 0, TAU); stroke(ctx, k.glow, 0.005, 0.7 * (1 - f / 0.3)); }
      const wy = y - p.s * (0.07 + 0.18 * lift) * sc;
      soft(ctx, x, wy, p.s * 0.3 * sc, k.glow, 0.6 * a); dot(ctx, x, wy, p.s * 0.07 * sc); fill(ctx, k.alt, a);
    },
  };

  // ================= Forgiveness =================
  // Round 1's knot, with a body: a thick rope that winds round itself when
  // held tight and lies as one easy wave when let go.
  F.forgive_knot = {
    label: 'a knot loosening', says: 'Forgiveness loosens what has been held tight.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const L = still ? 0.22 : 0.5 + 0.5 * S(t, 2 * B, -Math.PI / 2), M = 260, loops = lerp(2.5, 0, L), R = p.s * lerp(0.62, 0.9, L);
      soft(ctx, p.cx, p.cy, p.s * (0.45 + 0.6 * L), k.glow, 0.15 + 0.35 * L);
      ctx.beginPath();
      for (let i = 0; i <= M; i++) {
        const u = i / M, x0 = p.cx + p.s * lerp(-1.15, 1.15, u), env = Math.sin(Math.PI * u), a = TAU * (loops + 0.5) * u;
        const x = x0 - R * 0.95 * env * env * Math.sin(a) * (1 - L * 0.85), y = p.cy + R * 0.6 * env * env * Math.cos(a) * (1 - L) + p.s * 0.18 * L * Math.sin(TAU * u);
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      stroke(ctx, k.main, 0.026); // the same line twice: the rope, then its sheen
      ctx.lineWidth = 0.007; ctx.strokeStyle = css(mix(k.main, k.glow, 0.55), 0.55); ctx.stroke();
      [-1, 1].forEach((sd) => { dot(ctx, p.cx + sd * p.s * 1.15, p.cy, p.s * 0.06); fill(ctx, k.alt); });
    },
  };

  // Mended with gold: a bowl that broke, the break filled with gold. It
  // stays one bowl; the seam glows on the breath.
  F.forgive_mend = {
    label: 'mended with gold', says: 'Forgiveness: what broke is mended, and the mending made precious, not hidden.',
    build: (r, pl) => {
      const a0 = -Math.PI / 2 - 0.35, R = pl.s * 0.78, pts = [];
      for (let i = 0; i <= 7; i++) { const v = i / 7, x = lerp(Math.cos(a0), -Math.cos(a0), v) * R * 1.02, y = lerp(Math.sin(a0), -Math.sin(a0), v) * R * 1.02; pts.push([pl.cx + x + (i > 0 && i < 7 ? r.range(-0.12, 0.12) * R : 0), pl.cy + y]); }
      const bi = 3, br = [pts[bi], [pts[bi][0] + R * 0.32, pts[bi][1] + R * 0.12], [pts[bi][0] + R * 0.62, pts[bi][1] + R * 0.06]];
      return { ...pl, R, pts, br };
    },
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      soft(ctx, p.cx, p.cy, p.s * 1.25, k.glow, 0.15 + 0.12 * b);
      dot(ctx, p.cx, p.cy, p.R); fill(ctx, k.main, 0.88);
      ring(ctx, p.cx, p.cy, p.R * 0.8); stroke(ctx, k.paper, 0.004, 0.25);
      ctx.save(); dot(ctx, p.cx, p.cy, p.R); ctx.clip();
      [p.pts, p.br].forEach((line, j) => {
        ctx.beginPath(); line.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
        stroke(ctx, k.glow, j ? 0.014 : 0.022, 0.25 + 0.3 * b);
        ctx.beginPath(); line.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
        stroke(ctx, mix(k.alt, k.glow, 0.35 * b), j ? 0.005 : 0.008);
      });
      ctx.restore();
    },
  };

  // Hard edges softening: a sharp, cold shape eases into a round warm one
  // on a long breath — and, being human, sharpens a little, and softens again.
  F.forgive_soften = {
    label: 'the edges soften', says: 'Forgiveness: the hard edges of a grievance softening, again and again.',
    build: (r, pl) => ({ ...pl, n: 7, amp: Array.from({ length: 7 }, () => r.range(0.6, 1.1)), ph: r.range(0, TAU) }),
    draw(ctx, p, k, t, still) {
      const soft_ = still ? 0.55 : 0.5 - 0.5 * Math.cos(TAU * t / (2 * B)), R = p.s * 0.62, rot = still ? 0 : t * 0.01, M = 140;
      soft(ctx, p.cx, p.cy, p.s * (0.7 + 0.5 * soft_), k.glow, 0.1 + 0.45 * soft_);
      ctx.beginPath();
      for (let i = 0; i <= M; i++) {
        const th = TAU * i / M, w = frac(th * p.n / TAU), j = Math.floor(th * p.n / TAU) % p.n, tri = (1 - 4 * Math.abs(w - 0.5)) * p.amp[j];
        const rr = R * (1 + (1 - soft_) * 0.34 * tri + 0.03 * soft_ * Math.sin(3 * th + p.ph)), a = th + rot;
        const x = p.cx + rr * Math.cos(a), y = p.cy + rr * Math.sin(a); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.closePath(); fill(ctx, mix(k.main, k.alt, soft_), 0.9);
    },
  };

  // ================= The Mind Illuminated =================
  // The old elephant path, abstracted: a switchback climbing ten bends up
  // a mountain, the path growing lighter as it rises; a light climbs it.
  F.tmi_path = {
    label: 'the path up', says: 'The Mind Illuminated: ten stages, climbed bend by bend, the path growing lighter as it rises.',
    build: (r, pl) => ({ ...pl, P: Array.from({ length: 11 }, (_, i) => [pl.cx + (i % 2 ? 1 : -1) * pl.s * 0.85 * (1 - i / 13) + r.range(-0.03, 0.03) * pl.s, pl.cy + pl.s * (0.98 - 1.9 * i / 10)]) }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.62 : frac(t / (4 * B)), h = Math.min(10, u / 0.88 * 10), lit = (still ? 1 : C.ss(0, 0.03, u)) * (1 - C.ss(0.9, 1, u)), seg = (i) => { ctx.beginPath(); ctx.moveTo(p.P[i][0], p.P[i][1]); ctx.lineTo(p.P[i + 1][0], p.P[i + 1][1]); };
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.4, p.cy + p.s * 1.15); ctx.quadraticCurveTo(p.cx - p.s * 0.5, p.cy - p.s * 0.2, p.P[10][0], p.P[10][1] - p.s * 0.12); ctx.quadraticCurveTo(p.cx + p.s * 0.5, p.cy - p.s * 0.2, p.cx + p.s * 1.4, p.cy + p.s * 1.15); ctx.closePath(); fill(ctx, k.main, 0.13);
      for (let i = 0; i < 10; i++) { seg(i); stroke(ctx, k.main, 0.006, 0.28); }
      for (let i = 0; i < 10; i++) {
        const f = clamp(h - i, 0, 1); if (f <= 0) break;
        const [ax, ay] = p.P[i], [bx, by] = p.P[i + 1], e = i === Math.floor(h) ? C.easeInOut(f) : 1;
        ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(lerp(ax, bx, e), lerp(ay, by, e)); stroke(ctx, mix(k.main, k.glow, i / 9), 0.012, lit);
      }
      p.P.forEach(([x, y], i) => { const on = clamp(h - i + 1, 0, 1) * lit; dot(ctx, x, y, p.s * 0.035); fill(ctx, mix(k.main, k.glow, i / 10), 0.35 + 0.65 * on); });
      const i = Math.min(9, Math.floor(h)), e = C.easeInOut(clamp(h - i, 0, 1)), x = lerp(p.P[i][0], p.P[i + 1][0], e), y = lerp(p.P[i][1], p.P[i + 1][1], e), top = C.ss(9, 10, h) * lit;
      soft(ctx, p.P[10][0], p.P[10][1], p.s * 0.5, k.glow, 0.15 + 0.5 * top);
      soft(ctx, x, y, p.s * 0.25, k.glow, 0.6 * lit); dot(ctx, x, y, p.s * 0.055); fill(ctx, k.alt, lit);
    },
  };

  // From scattered to steady: one line in ten lengths, restless at the
  // start and calmer each stage, until the last is still and bright.
  F.tmi_steady = {
    label: 'scattered to steady', says: 'The Mind Illuminated: attention steadying stage by stage, from scattered to still and bright.',
    build: (r, pl) => ({ ...pl, ph: [r.range(0, TAU), r.range(0, TAU)] }),
    draw(ctx, p, k, t, still) {
      const x0 = p.cx - p.s * 1.2, x1 = p.cx + p.s * 1.2, M = 200, tt = still ? 3 : t;
      const Y = (v) => p.cy + p.s * 0.24 * Math.pow(1 - v, 1.6) * (0.6 * Math.sin(23 * v + tt * 1.3 + p.ph[0]) + 0.4 * Math.sin(41 * v - tt * 1.9 + p.ph[1]));
      for (let i = 1; i < 10; i++) { const x = lerp(x0, x1, i / 10); ctx.beginPath(); ctx.moveTo(x, p.cy - p.s * 0.42); ctx.lineTo(x, p.cy - p.s * 0.34); stroke(ctx, k.main, 0.004, 0.35); }
      for (let i = 0; i < M; i++) { const v = i / M, w = (i + 1) / M; ctx.beginPath(); ctx.moveTo(lerp(x0, x1, v), Y(v)); ctx.lineTo(lerp(x0, x1, w), Y(w)); stroke(ctx, mix(k.main, k.alt, C.ss(0.5, 1, v)), 0.008 + 0.006 * v, 0.55 + 0.45 * v); }
      soft(ctx, x1, p.cy, p.s * 0.45, k.glow, 0.5);
      const u = still ? 0.7 : frac(t / (4 * B)), v = C.easeInOut(u), x = lerp(x0, x1, v);
      soft(ctx, x, Y(v), p.s * 0.22, k.glow, 0.6 * fade(u)); dot(ctx, x, Y(v), p.s * 0.05); fill(ctx, k.alt, fade(u));
    },
  };

  // A ten-petalled flower opening one petal at a time, from the top round;
  // when all ten are open it rests, then closes, and begins again.
  F.tmi_petals = {
    label: 'ten petals opening', says: 'The Mind Illuminated: ten stages unfolding one after another, like petals.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const u = still ? 0.62 : frac(t / (4 * B)), close = 1 - C.ss(0.86, 1, u);
      let n = 0;
      for (let i = 0; i < 10; i++) {
        const o = C.ss(i * 0.075, i * 0.075 + 0.1, u) * close, a = -Math.PI / 2 + TAU * i / 10; n += o;
        petal(ctx, p.cx + Math.cos(a) * p.s * 0.16, p.cy + Math.sin(a) * p.s * 0.16, p.s * (0.25 + 0.68 * o), p.s * (0.07 + 0.11 * o), a);
        fill(ctx, mix(k.main, k.alt, o), 0.3 + 0.6 * o);
      }
      soft(ctx, p.cx, p.cy, p.s * (0.3 + 0.05 * n), k.glow, 0.3 + 0.04 * n);
      dot(ctx, p.cx, p.cy, p.s * 0.12); fill(ctx, k.alt);
    },
  };

  // Steadying upwards (Burooj, 2026-11-03: A and B combined). One path
  // climbs; low down the line wavers, scattered, and it steadies as it
  // rises, smooth and bright near the top. Ten stage marks sit along it and
  // a light climbs it. No triangle: the path alone implies the mountain.
  function climbDraw(ctx, p, k, t, still) {
    const N = p.pts.length, tt = still ? 3 : t, off = (v) => p.s * 0.1 * Math.pow(1 - v, 1.7) * (0.6 * Math.sin(37 * v + tt * 1.4 + p.ph[0]) + 0.4 * Math.sin(61 * v - tt * 2.1 + p.ph[1]));
    const at = (i) => { const v = i / (N - 1), o = off(v); return [p.pts[i][0] + p.nx[i] * o, p.pts[i][1] + p.ny[i] * o]; };
    const u = still ? 0.62 : frac(t / (4 * B)), h = Math.min(1, u / 0.88), lit = (still ? 1 : C.ss(0, 0.03, u)) * (1 - C.ss(0.9, 1, u));
    soft(ctx, p.pts[N - 1][0], p.pts[N - 1][1], p.s * 0.5, k.glow, 0.15 + 0.45 * C.ss(0.85, 1, h) * lit);
    let prev = at(0);
    for (let i = 1; i < N; i++) { const v = i / (N - 1), q = at(i); ctx.beginPath(); ctx.moveTo(prev[0], prev[1]); ctx.lineTo(q[0], q[1]); stroke(ctx, mix(k.main, k.glow, C.ss(0.35, 1, v)), 0.007 + 0.006 * v, 0.55 + 0.45 * v); prev = q; }
    for (let j = 0; j < 10; j++) { const v = (j + 0.5) / 10, i = Math.round(v * (N - 1)), [x, y] = at(i), on = C.ss(v - 0.02, v + 0.02, h) * lit; dot(ctx, x, y, p.s * 0.03); fill(ctx, mix(k.main, k.glow, C.ss(0.35, 1, v)), 0.4 + 0.6 * on); }
    const [x, y] = at(Math.round(C.easeInOut(h) * (N - 1)));
    soft(ctx, x, y, p.s * 0.25, k.glow, 0.6 * lit); dot(ctx, x, y, p.s * 0.055); fill(ctx, k.alt, lit);
  }
  function climbPath(raw, pl, r) { const { pts } = C.resample(raw, 240), { nx, ny } = C.normals(pts, 2); return { ...pl, pts, nx, ny, ph: [r.range(0, TAU), r.range(0, TAU)] }; }

  // A rounded switchback, five legs of even width, ten marks along it.
  F.tmi_switchback = {
    label: 'steadying upwards', says: 'The Mind Illuminated: ten stages up one winding path, the line wavering low down and steadying as it climbs.',
    build(r, pl) {
      const legs = 5, W = pl.s * 0.72, y0 = pl.cy + pl.s * 0.95, y1 = pl.cy - pl.s * 0.9, dy = (y0 - y1) / legs, R = dy * 0.32, pen = C.pen(pl.cx - W, y0);
      for (let i = 0; i < legs; i++) {
        const dir = i % 2 ? -1 : 1, yEnd = y0 - (i + 1) * dy + (i < legs - 1 ? R : 0), xEnd = pl.cx + dir * W;
        pen.cubic(pl.cx - dir * W * 0.3, y0 - i * dy - dy * 0.15, pl.cx + dir * W * 0.3, yEnd + dy * 0.15, xEnd, yEnd, 70);
        if (i < legs - 1) pen.arc(xEnd, yEnd - R, R, R, Math.PI / 2, dir > 0 ? -Math.PI / 2 : Math.PI * 1.5, 40); // round the bend, bottom to top
      }
      return climbPath(pen.pts, pl, r);
    },
    draw: climbDraw,
  };

  // One trail up a hillside: a long, gently winding climb from low left to
  // high right over a soft hill, steadying as it goes.
  F.tmi_climb = {
    label: 'the long climb', says: 'The Mind Illuminated: one long climb through ten stages, from a scattered start to steady, bright attention.',
    build(r, pl) {
      const raw = C.pen(pl.cx - pl.s * 1.25, pl.cy + pl.s * 0.85).cubic(pl.cx - pl.s * 0.1, pl.cy + pl.s * 0.95, pl.cx - pl.s * 0.9, pl.cy + pl.s * 0.1, pl.cx + pl.s * 0.1, pl.cy - pl.s * 0.05, 90).cubic(pl.cx + pl.s * 1.0, pl.cy - pl.s * 0.2, pl.cx + 0.1 * pl.s, pl.cy - pl.s * 0.75, pl.cx + pl.s * 0.85, pl.cy - pl.s * 0.85, 90).pts;
      return climbPath(raw, pl, r);
    },
    draw(ctx, p, k, t, still) {
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 1.8, p.cy + p.s * 1.2); ctx.bezierCurveTo(p.cx - p.s * 0.6, p.cy + p.s * 0.6, p.cx + p.s * 0.2, p.cy - p.s * 1.05, p.cx + p.s * 0.95, p.cy - p.s * 0.98); ctx.bezierCurveTo(p.cx + p.s * 1.3, p.cy - p.s * 0.95, p.cx + p.s * 1.6, p.cy - p.s * 0.6, p.cx + p.s * 1.8, p.cy - p.s * 0.4); ctx.lineTo(p.cx + p.s * 1.8, p.cy + p.s * 1.2); ctx.closePath(); fill(ctx, k.main, 0.08);
      climbDraw(ctx, p, k, t, still);
    },
  };

  // ================= Anussati =================
  // Three soft lights, recollected one after another; each warms in turn.
  F.jewels_lights = {
    label: 'three lights', says: 'Anussati: the Buddha, the Dhamma and the Saṅgha, recollected one by one, each warming in turn.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      [[0, -0.46], [-0.52, 0.38], [0.52, 0.38]].forEach(([dx, dy], i) => {
        const x = p.cx + dx * p.s, y = p.cy + dy * p.s, on = still ? (i === 0 ? 1 : 0.3) : 0.3 + 0.7 * Math.pow(fade(frac(t / (3 * B) - i / 3) * 1.5), 2), R = p.s * 0.17;
        soft(ctx, x, y, p.s * 0.55, k.glow, 0.6 * on);
        const g = ctx.createRadialGradient(x - R * 0.3, y - R * 0.3, 0, x, y, R); g.addColorStop(0, css(mix(k.glow, '#FFFFFF', 0.55))); g.addColorStop(1, css(k.alt));
        ctx.globalAlpha = 0.45 + 0.55 * on; ctx.fillStyle = g; dot(ctx, x, y, R); ctx.fill(); ctx.globalAlpha = 1;
      });
    },
  };

  // The triple gem as the tradition draws it: three jewels, two below and
  // one above, in a halo of flame; the light passes over each in turn.
  F.jewels_gem = {
    label: 'the triple gem', says: 'Anussati: the three jewels, one refuge — recollected one by one.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.26, J = [[0, -0.26], [-0.26, 0.19], [0.26, 0.19]], fl = still ? 0 : 0.02 * S(t, 3.1);
      soft(ctx, p.cx, p.cy, p.s * 1.1, k.glow, 0.3 + 0.1 * b);
      tear(ctx, p.cx, p.cy + p.s * 0.2, p.s * (1.12 + fl), p.s * 0.82); fill(ctx, k.glow, 0.22); stroke(ctx, k.alt, 0.006, 0.6);
      J.forEach(([dx, dy], i) => {
        const x = p.cx + dx * p.s, y = p.cy + dy * p.s, on = still ? (i === 0 ? 1 : 0.35) : 0.35 + 0.65 * Math.pow(fade(frac(t / (3 * B) - i / 3) * 1.5), 2);
        const g = ctx.createRadialGradient(x - R * 0.35, y - R * 0.35, 0, x, y, R); g.addColorStop(0, css(mix(k.glow, '#FFFFFF', 0.3 + 0.4 * on))); g.addColorStop(0.55, css(mix(k.alt, k.glow, 0.3 * on))); g.addColorStop(1, css(mix(k.alt, k.main, 0.35)));
        ctx.fillStyle = g; dot(ctx, x, y, R); ctx.fill();
      });
    },
  };

  // Three rings, each through the other two, none of them free alone: the
  // three refuges as one. Each brightens in turn.
  F.jewels_weave = {
    label: 'three as one', says: 'Anussati: three refuges, each held by the other two, recollected one by one.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const R = p.s * 0.5, d = p.s * 0.32, cols = [k.glow, k.alt, mix(k.main, k.glow, 0.3)];
      const C3 = [0, 1, 2].map((i) => { const a = -Math.PI / 2 + TAU * i / 3; return [p.cx + Math.cos(a) * d, p.cy + Math.sin(a) * d]; });
      const on = (i) => (still ? (i === 0 ? 1 : 0.4) : 0.4 + 0.6 * Math.pow(fade(frac(t / (3 * B) - i / 3) * 1.5), 2));
      soft(ctx, p.cx, p.cy, p.s * 0.4, k.glow, 0.5);
      const arc = (i, a0, a1, w, col, al) => { ctx.beginPath(); ctx.arc(C3[i][0], C3[i][1], R, a0, a1); stroke(ctx, col, w, al); };
      [0, 1, 2].forEach((i) => arc(i, 0, TAU, 0.022, cols[i], 0.55 + 0.45 * on(i)));
      // each ring passes over the next at both crossings: 0 over 1, 1 over 2, 2 over 0
      [[0, 1], [1, 2], [2, 0]].forEach(([i, j]) => {
        const [ax, ay] = C3[i], [bx, by] = C3[j], D = Math.hypot(bx - ax, by - ay), x = D / 2, h = Math.sqrt(R * R - x * x), ux = (bx - ax) / D, uy = (by - ay) / D;
        [-1, 1].forEach((sd) => { const px = ax + ux * x - uy * h * sd, py = ay + uy * x + ux * h * sd, a = Math.atan2(py - ay, px - ax); arc(i, a - 0.28, a + 0.28, 0.04, k.paper, 1); arc(i, a - 0.3, a + 0.3, 0.022, cols[i], 0.55 + 0.45 * on(i)); });
      });
    },
  };

  // ================= Karuṇā =================
  // Tonglen without the eye: on the in-breath, dark motes drawn in to a
  // warm heart, where they vanish; on the out-breath, a ring of ease goes out.
  F.karuna_breath = {
    label: 'taking in, sending out', says: 'Karuṇā as tonglen: breathing in what hurts, breathing out ease.',
    build: (r, pl) => ({ ...pl, m: Array.from({ length: 14 }, (_, i) => ({ a: TAU * i / 14 + r.range(-0.2, 0.2), d: r.range(0.9, 1.3), z: r.range(0.03, 0.05) })) }),
    draw(ctx, p, k, t, still) {
      const ph = still ? 0.3 : frac(t / B), inhale = ph < 0.5, u = inhale ? ph * 2 : (ph - 0.5) * 2, b = BR(t, still);
      soft(ctx, p.cx, p.cy, p.s * 0.6, k.glow, 0.4 + 0.2 * b);
      if (inhale) p.m.forEach((m) => { const r = p.s * lerp(m.d * 1.15, 0.12, easeIn(u)), a = m.a + u * 0.4; dot(ctx, p.cx + Math.cos(a) * r, p.cy + Math.sin(a) * r, p.s * m.z * (1 - 0.6 * u)); fill(ctx, k.main, 0.75 * fade(u)); });
      else { ring(ctx, p.cx, p.cy, p.s * lerp(0.25, 1.3, C.easeOut(u))); stroke(ctx, k.glow, 0.022 * (1 - u) + 0.004, 0.85 * fade(u)); soft(ctx, p.cx, p.cy, p.s * lerp(0.3, 1.2, u), k.glow, 0.3 * (1 - u)); }
      C.blobPath(ctx, p._b || Object.defineProperty(p, '_b', { value: C.makeBlob(C.makeRng('karuna'), p.cx, p.cy, p.s * 0.15, 0.8, 0), enumerable: false })._b, { imperf: 0.6, grow: 0.95 + 0.1 * b }); fill(ctx, k.alt);
    },
  };

  // Held: something small and trembling, cradled by a wide warm curve; on
  // each out-breath it trembles less and warms.
  F.karuna_hold = {
    label: 'held', says: 'Karuṇā: suffering held with care, and easing in the holding.',
    build: (r, pl) => ({ ...pl, blob: C.makeBlob(r, pl.cx, pl.cy + pl.s * 0.12, pl.s * 0.2, 2.2, 0) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), calm = 1 - b, lift = p.s * 0.03 * b, jit = still ? 0 : (1 - calm) * p.s * 0.012 * S(t, 0.6);
      soft(ctx, p.cx, p.cy + p.s * 0.1, p.s * (0.75 + 0.1 * b), k.glow, 0.35 + 0.15 * calm);
      [[0.82, 0.024, 1], [0.68, 0.01, 0.5]].forEach(([rr, w, a]) => { ctx.beginPath(); ctx.arc(p.cx, p.cy - p.s * 0.28 - lift, p.s * rr, Math.PI * 0.18, Math.PI * 0.82); stroke(ctx, k.alt, w, a); });
      C.blobPath(ctx, p.blob, { dx: jit, dy: -lift, imperf: 0.4 + 0.6 * b, grow: 0.95 + 0.05 * calm }); fill(ctx, mix(k.main, k.glow, 0.25 + 0.5 * calm));
    },
  };

  // Dark rising into a warm heart, and light rising out of it: the whole
  // practice as one quiet, unending flow.
  F.karuna_rise = {
    label: 'dark into light', says: 'Karuṇā: what is dark taken into the heart, and coming out as light.',
    build: (r, pl) => ({ ...pl, m: Array.from({ length: 20 }, (_, i) => ({ ox: r.range(-0.7, 0.7), ph: i / 20 + r.range(-0.02, 0.02), z: r.range(0.022, 0.04) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still);
      soft(ctx, p.cx, p.cy, p.s * (0.6 + 0.08 * b), k.glow, 0.5);
      p.m.forEach((m) => {
        const u = still ? frac(m.ph + 0.02) : frac(t / (1.6 * B) + m.ph), y = p.cy + p.s * lerp(1.15, -1.15, u), lower = u < 0.5;
        const x = p.cx + m.ox * p.s * (lower ? 1 - easeIn(u * 2) : C.easeOut((u - 0.5) * 2) * 1.2), a = fade(u) * C.ss(0.03, 0.14, Math.abs(u - 0.5));
        dot(ctx, x, y, p.s * m.z); fill(ctx, mix(k.main, k.glow, C.ss(0.4, 0.6, u)), a);
      });
      dot(ctx, p.cx, p.cy, p.s * (0.16 + 0.02 * b)); fill(ctx, k.alt);
    },
  };

  // ================= Jhāna =================
  // Round 1's gathering, without the rays: joy scattered about gathers into
  // one soft light with no edge.
  F.jhana_gather = {
    label: 'light gathering in', says: 'Jhāna: scattered joy gathers into one soft, still light.',
    build: (r, pl) => ({ ...pl, motes: Array.from({ length: 30 }, () => ({ a: r.range(0, TAU), d: r.range(0.7, 1.3), ph: r.next(), sz: r.range(0.02, 0.04) })) }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), core = mix(k.glow, '#FFFFFF', 0.5);
      p.motes.forEach((m) => { const u = still ? m.ph : frac(t / (2 * B) + m.ph), rr = p.s * m.d * (1 - C.easeInOut(u) * 0.85), a = m.a + u * 0.6; dot(ctx, p.cx + Math.cos(a) * rr, p.cy + Math.sin(a) * rr, p.s * m.sz * (1 - 0.5 * u)); fill(ctx, k.alt, 0.85 * fade(u)); });
      soft(ctx, p.cx, p.cy, p.s * (0.85 + 0.12 * b), k.glow, 0.45);
      const g = ctx.createRadialGradient(p.cx, p.cy, 0, p.cx, p.cy, p.s * (0.42 + 0.04 * b)); g.addColorStop(0, css(core, 1)); g.addColorStop(0.45, css(core, 0.9)); g.addColorStop(1, css(k.glow, 0));
      ctx.fillStyle = g; dot(ctx, p.cx, p.cy, p.s * 0.5); ctx.fill();
    },
  };

  // The second jhāna's simile: a lake fed from a spring beneath, cool water
  // welling up until no part of it is not pervaded.
  F.jhana_spring = {
    label: 'a spring-fed lake', says: 'Jhāna: like a lake fed by a spring below, cool water welling up until it fills every part.',
    build: (r, pl) => ({ ...pl }),
    draw(ctx, p, k, t, still) {
      const b = BR(t, still), R = p.s * 0.98, cool = mix(k.glow, '#FFFFFF', 0.45);
      dot(ctx, p.cx, p.cy, R); fill(ctx, mix(k.main, k.paper, 0.55), 0.7);
      ctx.save(); dot(ctx, p.cx, p.cy, R); ctx.clip();
      for (let i = 0; i < 4; i++) {
        const u = still ? (i + 0.4) / 4 : frac(t / (3 * B) + i / 4), rr = R * 1.1 * u, w = R * 0.22, a = 0.45 * fade(u);
        const g = ctx.createRadialGradient(p.cx, p.cy, Math.max(0, rr - w), p.cx, p.cy, rr + w); g.addColorStop(0, css(cool, 0)); g.addColorStop(0.5, css(cool, a)); g.addColorStop(1, css(cool, 0));
        ctx.fillStyle = g; dot(ctx, p.cx, p.cy, rr + w); ctx.fill();
      }
      soft(ctx, p.cx, p.cy, R, cool, 0.12 + 0.18 * b);
      ctx.restore();
      ring(ctx, p.cx, p.cy, R); stroke(ctx, k.main, 0.006, 0.45);
      dot(ctx, p.cx, p.cy, p.s * 0.05); fill(ctx, cool);
    },
  };

  // The third jhāna's simile: lotuses that grow in the water and never rise
  // out of it, drenched with cool water from root to tip.
  F.jhana_lotus = {
    label: 'lotuses in the water', says: 'Jhāna: like lotuses under water, drenched in coolness from root to tip.',
    build: (r, pl) => ({ ...pl, L: [[-0.62, 0.42], [0.06, 0.56], [0.68, 0.38]].map(([dx, ls]) => ({ dx, ls, p: { ...Prims.lotus.build(r, { cx: 0, cy: 0, s: ls * pl.s }), water: false, tiers: 1 } })), bub: Array.from({ length: 10 }, () => ({ x: r.range(-1.1, 1.1), ph: r.next(), z: r.range(0.012, 0.025) })) }),
    draw(ctx, p, k, t, still) {
      const wl = p.cy - p.s * 0.5, bot = p.cy + p.s * 1.0, cool = mix(k.glow, '#FFFFFF', 0.4);
      p.L.forEach((l, i) => {
        const base = p.cy + p.s * 0.9, ls = l.ls * p.s, q = l.p, sway = still ? 0 : 0.05 * S(t, 7 + i * 1.7, i);
        q.cx = p.cx + l.dx * p.s; q.cy = base - 0.55 * ls;
        ctx.save(); ctx.translate(q.cx, base); ctx.rotate(sway); ctx.translate(-q.cx, -base);
        ctx.beginPath(); ctx.moveTo(q.cx, base); ctx.lineTo(q.cx, bot + p.s * 0.3); stroke(ctx, k.main, 0.006, 0.6);
        Prims.lotus.draw(ctx, q, { ...k, main: mix(k.alt, k.main, 0.25), alt: k.glow }, t, still); ctx.restore();
      });
      const wg = ctx.createLinearGradient(0, wl, 0, bot); wg.addColorStop(0, css(mix(k.paper, '#FFFFFF', 0.5), 0.45)); wg.addColorStop(1, css(mix(k.paper, cool, 0.3), 0.15)); ctx.fillStyle = wg; ctx.fillRect(p.cx - p.s * 2, wl, p.s * 4, p.s * 3);
      ctx.beginPath(); ctx.moveTo(p.cx - p.s * 2, wl); ctx.lineTo(p.cx + p.s * 2, wl); stroke(ctx, k.main, 0.006, 0.5);
      p.bub.forEach((q) => { const u = still ? q.ph : frac(t / (2.4 * B) + q.ph); dot(ctx, p.cx + q.x * p.s, lerp(bot, wl + p.s * 0.05, u), p.s * q.z); fill(ctx, cool, 0.8 * fade(u)); });
      [0, 1].forEach((i) => { pill(ctx, p.cx + p.s * (i ? 0.5 : -0.4) + (still ? 0 : p.s * 0.05 * S(t, 9 + i * 3)), wl + p.s * 0.05, p.s * 0.4, p.s * 0.025, 0); fill(ctx, cool, 0.6); });
    },
  };

  return F;
})();
