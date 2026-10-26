/* Round 2 art: a generator per sound kind for the Sounds tab, preset cards
 * that blend their layers, and seeded covers for courses, playlists,
 * teachers and singles. All of it paints in the active palette and gets the
 * same print finish as the marks. A card is unit-wide and H tall. */
const Art = (() => {
  'use strict';
  const C = Core, { TAU, lerp, clamp, css, mix } = C;

  // From assets/sounds/sounds.json, plus the synth layers.
  const SOUNDS = [
    ['rain-terrace', 'Rain on a terrace', 'rain'], ['rain-umbrella', 'Rain on an umbrella', 'rain'], ['rain-window', 'Rain at the window', 'rain'], ['rain-car', 'Rain on a car roof', 'rain'],
    ['stream', 'Mountain stream', 'water'], ['river', 'River', 'water'], ['waves', 'Small waves', 'water'], ['sea', 'Beach at Dellec', 'water'],
    ['wind-trees', 'Wind in the trees', 'wind'], ['wind-grass', 'Wind in tall grass', 'wind'],
    ['forest-birds', 'Forest birds', 'forest'], ['dawn-chorus', 'Dawn chorus', 'forest'], ['evening-birds', 'Evening birds', 'forest'], ['forest-brook', 'Forest brook', 'forest'],
    ['fire-crackle', 'Crackling fire', 'fire'], ['fire-stove', 'Wood stove', 'fire'],
    ['room-house', 'Quiet house', 'room'], ['cafe', 'Café', 'room'], ['train', 'Metro carriage', 'room'],
    ['night-meadow', 'Meadow at night', 'night'], ['night-insects', 'Night insects', 'night'], ['night-frogs', 'Frogs by a pond', 'night'],
    ['noise-white', 'White noise', 'synth'], ['noise-pink', 'Pink noise', 'synth'], ['noise-brown', 'Brown noise', 'synth'], ['drone', 'Drone · 110 Hz', 'synth'], ['binaural', 'Binaural · theta', 'synth'],
  ].map(([id, title, cat]) => ({ id, title, cat }));
  const KIND = (id) => id.startsWith('rain') ? 'rain' : id === 'stream' || id === 'river' ? 'flow' : id === 'waves' || id === 'sea' ? 'sea' : id.startsWith('wind') ? 'wind'
    : ['forest-birds', 'dawn-chorus', 'evening-birds', 'forest-brook'].includes(id) ? 'forest' : id.startsWith('fire') ? 'fire' : ['room-house', 'cafe', 'train'].includes(id) ? 'room'
    : id.startsWith('night') ? 'night' : id.startsWith('noise') ? 'noise' : id;
  const PRESETS = [
    { id: 'starter-rain-forest', title: 'Rain on the forest', layers: [['rain-terrace', 0.7], ['forest-birds', 0.45], ['wind-trees', 0.3]] },
    { id: 'starter-night', title: 'Night', layers: [['night-meadow', 0.6], ['stream', 0.35]] },
    { id: 'starter-hearth', title: 'Hearth', layers: [['fire-stove', 0.6], ['fire-crackle', 0.55], ['rain-window', 0.4]] },
    { id: 'starter-shore', title: 'Shore', layers: [['waves', 0.7], ['wind-grass', 0.3]] },
    { id: 'starter-stillness', title: 'Stillness', layers: [['noise-brown', 0.55], ['drone', 0.35]] },
    { id: 'user-morning', title: 'Morning sit (yours)', layers: [['dawn-chorus', 0.6], ['forest-brook', 0.4], ['binaural', 0.3]] },
  ];

  // ---------- sound scenes ----------
  function buildSound(id) {
    const r = C.makeRng('sound:' + id), kind = KIND(id), s = { id, kind, r: C.makeRng('sound-live:' + id) };
    s.streaks = Array.from({ length: 70 }, () => ({ x: r.range(-0.1, 1.1), y: r.next(), v: r.range(0.06, 0.12), l: r.range(0.04, 0.09), a: r.range(0.18, 0.5) }));
    s.dots = Array.from({ length: 40 }, () => ({ x: r.next(), y: r.next(), r: r.range(0.002, 0.006), ph: r.range(0, TAU), sp: r.range(0.3, 1.2), a: r.range(0.3, 1) }));
    s.bokeh = Array.from({ length: 18 }, () => ({ x: r.next(), y: r.range(0.1, 0.9), r: r.range(0.03, 0.11), ph: r.range(0, TAU), role: r.pick(['accent', 'accent', 'light', 'form']), a: r.range(0.25, 0.6) }));
    s.lines = Array.from({ length: 12 }, () => ({ y: r.next(), ph: r.range(0, TAU), l: r.range(0.25, 0.6), v: r.range(0.015, 0.035), amp: r.range(0.01, 0.03), f: r.range(1, 2.5) }));
    s.ribbons = Array.from({ length: 6 }, (_, i) => ({ y: lerp(0.25, 0.85, i / 5) + r.range(-0.05, 0.05), amp: r.range(0.03, 0.07), f: r.range(0.8, 1.8), ph: r.range(0, TAU), w: r.range(0.015, 0.05), v: r.range(0.02, 0.05) }));
    s.crowns = Array.from({ length: 3 }, (_, i) => Array.from({ length: 9 }, (_, j) => ({ x: j / 8 + r.range(-0.05, 0.05), r: r.range(0.08, 0.15) * (1 + i * 0.25), dy: r.range(-0.03, 0.03), ph: r.range(0, TAU) })));
    s.flames = Array.from({ length: 5 }, () => ({ x: r.range(-0.12, 0.12), h: r.range(0.2, 0.36), w: r.range(0.06, 0.1), ph: r.range(0, TAU) }));
    s.birds = Array.from({ length: 4 }, () => ({ x: r.next(), y: r.range(0.12, 0.35), s: r.range(0.012, 0.022), v: r.range(0.008, 0.02), ph: r.range(0, TAU) }));
    s.glow = { x: r.range(0.25, 0.75), y: r.range(0.2, 0.5) };
    s.hy = r.range(0.38, 0.46);
    return s;
  }
  const hn = (t, k) => 0.5 + 0.5 * (0.6 * Math.sin(t * 2.3 + k) * Math.sin(t * 1.7 + k * 2) + 0.4 * Math.sin(t * 5.1 + k * 3));
  function radial(ctx, x, y, r, col, a) { const g = ctx.createRadialGradient(x, y, 0, x, y, r); g.addColorStop(0, css(col, a)); g.addColorStop(1, css(col, 0)); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill(); }
  function vgrad(ctx, H, stops) { const g = ctx.createLinearGradient(0, 0, 0, H); stops.forEach(([k, col, a]) => g.addColorStop(k, css(col, a ?? 1))); ctx.fillStyle = g; ctx.fillRect(0, 0, 1, H); }

  // Each kind has its own key, all drawn from the palette: rain sits grey
  // and dim, sea and wind open up, fire and night go deep. The scrim keeps a
  // light title readable on all of them.
  const dark = (c, k = 0.3) => mix(c.deep, c.form, k);
  const pale = (c, k = 0.3) => mix(c.tile, c.accent, k);
  const BG = {
    rain(ctx, s, c, H) { const g = mix(c.deep, c.tile, 0.22); vgrad(ctx, H, [[0, mix(g, c.form, 0.2)], [1, mix(c.deep, c.form, 0.12)]]); radial(ctx, s.glow.x, s.glow.y * H, 0.5, c.accent, 0.22); },
    flow(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(c.form, c.tile, 0.25)], [0.5, c.form], [1, dark(c, 0.55)]]); },
    sea(ctx, s, c, H) { const hy = s.hy; vgrad(ctx, H, [[0, mix(c.form, c.tile, 0.45)], [hy, pale(c, 0.55)], [hy + 0.002, mix(c.form, c.deep, 0.3)], [1, dark(c, 0.35)]]); radial(ctx, s.glow.x, hy * H, 0.4, c.accent, 0.5); },
    wind(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(c.tile, c.form, 0.55)], [1, mix(c.form, c.deep, 0.45)]]); },
    forest(ctx, s, c, H) {
      const sky = s.id === 'dawn-chorus' ? pale(c, 0.5) : s.id === 'evening-birds' ? mix(c.accent, c.deep, 0.45) : mix(c.tile, c.form, 0.4);
      vgrad(ctx, H, [[0, mix(sky, c.deep, 0.15)], [0.65, sky], [1, dark(c, 0.4)]]);
      radial(ctx, s.glow.x, 0.6 * H, 0.45, c.accent, s.id === 'forest-birds' ? 0.15 : 0.45);
    },
    fire(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(c.deep, c.tile, 0.04)], [1, dark(c, 0.25)]]); },
    room(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(dark(c, 0.3), c.accent, 0.15)], [1, dark(c, 0.15)]]); },
    night(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(c.deep, c.tile, 0.03)], [0.75, mix(c.deep, c.form, 0.28)], [1, c.deep]]); radial(ctx, s.glow.x, 0.2 * H, 0.06, c.light, 0.8); radial(ctx, s.glow.x, 0.2 * H, 0.3, c.light, 0.12); },
    noise(ctx, s, c, H) { const k = s.id === 'noise-white' ? mix(c.tile, c.form, 0.15) : s.id === 'noise-pink' ? mix(c.form, c.accent, 0.45) : dark(c, 0.55); vgrad(ctx, H, [[0, k], [1, mix(k, c.deep, 0.3)]]); },
    drone(ctx, s, c, H) { vgrad(ctx, H, [[0, dark(c, 0.2)], [1, dark(c, 0.4)]]); },
    binaural(ctx, s, c, H) { vgrad(ctx, H, [[0, mix(c.deep, c.stroke === c.deep ? c.form : c.stroke, 0.12)], [1, dark(c, 0.35)]]); },
  };
  // Foreground elements can sit on any field, so presets can layer them.
  const FG = {
    rain(ctx, s, c, H, t, a) {
      if (s.id === 'rain-window' && a > 0.6) { ctx.strokeStyle = css(c.light, 0.18 * a); ctx.lineWidth = 0.012; ctx.strokeRect(0.08, 0.08 * H, 0.84, H * 0.84); ctx.beginPath(); ctx.moveTo(0.5, 0.08 * H); ctx.lineTo(0.5, 0.92 * H); ctx.stroke(); }
      if (s.id === 'rain-umbrella' && a > 0.6) { ctx.beginPath(); ctx.ellipse(0.5, 0, 0.62, 0.2 * H + 0.08, 0, 0, Math.PI); ctx.fillStyle = css(c.deep, 0.85); ctx.fill(); }
      if (s.id === 'rain-car' && a > 0.6) { ctx.beginPath(); ctx.moveTo(-0.1, H); ctx.quadraticCurveTo(0.5, H * 0.62, 1.1, H); ctx.fillStyle = css(dark(c, 0.05), 0.9); ctx.fill(); }
      if (s.id === 'rain-terrace' && a > 0.6) { ctx.strokeStyle = css(c.light, 0.12); ctx.lineWidth = 0.004; for (let i = 0; i < 5; i++) { const y = H * (0.72 + i * i * 0.012); ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(1, y); ctx.stroke(); } }
      ctx.lineCap = 'round';
      for (const p of s.streaks) {
        const y = ((p.y + t * p.v) % 1.15) - 0.1, x = p.x - y * 0.12;
        ctx.strokeStyle = css(c.light, p.a * a); ctx.lineWidth = 0.0035;
        ctx.beginPath(); ctx.moveTo(x, y * H); ctx.lineTo(x - p.l * 0.12, (y + p.l) * H); ctx.stroke();
      }
    },
    flow(ctx, s, c, H, t, a) {
      const diag = s.id === 'stream' ? 0.35 : 0.08;
      s.ribbons.forEach((R, i) => {
        const y0 = lerp(0.35, 1, (i + 0.5) / s.ribbons.length) * H, top = [], bot = [];
        for (let x = -0.1; x <= 1.1; x += 0.025) {
          const ph = TAU * R.f * x - t * R.v * 12 + R.ph, y = y0 - diag * (x - 0.5) * H + R.amp * H * Math.sin(ph), w = R.w * H * (0.6 + 0.4 * Math.sin(ph * 0.5 + 1));
          top.push([x, y - w]); bot.push([x, y + w]);
        }
        ctx.beginPath(); top.forEach(([x, y], j) => (j ? ctx.lineTo(x, y) : ctx.moveTo(x, y))); bot.reverse().forEach(([x, y]) => ctx.lineTo(x, y)); ctx.closePath();
        ctx.fillStyle = css(i % 2 ? c.light : mix(c.form, c.light, 0.4), (0.16 + 0.05 * (i % 3)) * a); ctx.fill();
      });
    },
    sea(ctx, s, c, H, t, a) {
      for (let i = 0; i < 6; i++) {
        const k = i / 5, y0 = (s.hy + 0.03 + Math.pow(k, 1.4) * (1 - s.hy)) * H, amp = (0.004 + 0.018 * k) * H, ph = t * (0.25 + 0.1 * i) + i * 1.3;
        ctx.beginPath(); ctx.moveTo(-0.05, H + 0.1);
        for (let x = -0.05; x <= 1.05; x += 0.02) ctx.lineTo(x, y0 + amp * Math.sin(TAU * x * (1.2 + i * 0.25) + ph));
        ctx.lineTo(1.05, H + 0.1); ctx.closePath();
        ctx.fillStyle = css(mix(dark(c, 0.45 - k * 0.3), c.deep, k * 0.4), 0.55 * a); ctx.fill();
        ctx.strokeStyle = css(c.light, (0.35 - 0.2 * k) * a); ctx.lineWidth = 0.004; ctx.stroke();
      }
      if (s.id === 'sea' && a > 0.6) { ctx.beginPath(); ctx.moveTo(0, H * 0.9); ctx.quadraticCurveTo(0.5, H * 0.84, 1, H * 0.88); ctx.lineTo(1, H); ctx.lineTo(0, H); ctx.fillStyle = css(mix(c.accent, c.deep, 0.55), 0.85); ctx.fill(); }
    },
    wind(ctx, s, c, H, t, a) {
      ctx.lineCap = 'round';
      for (const L of s.lines) {
        const x0 = ((L.ph / TAU + t * L.v) % 1.6) - 0.5, y = L.y * H * 0.8 + 0.05;
        ctx.beginPath();
        for (let i = 0; i <= 30; i++) { const u = i / 30, x = x0 + u * L.l; const yy = y + L.amp * Math.sin(TAU * L.f * u + t * 0.6 + L.ph); i ? ctx.lineTo(x, yy) : ctx.moveTo(x, yy); }
        const g = ctx.createLinearGradient(x0, 0, x0 + L.l, 0); g.addColorStop(0, css(c.light, 0)); g.addColorStop(0.5, css(c.light, 0.45 * a)); g.addColorStop(1, css(c.light, 0));
        ctx.strokeStyle = g; ctx.lineWidth = 0.004; ctx.stroke();
      }
      if (s.id === 'wind-grass') {
        for (let i = 0; i < 60; i++) { const x = i / 59, h = (0.18 + 0.12 * Math.sin(i * 7.3)) * H, bend = 0.04 * Math.sin(t * 0.7 + x * 3) + 0.03; ctx.beginPath(); ctx.moveTo(x, H); ctx.quadraticCurveTo(x, H - h * 0.6, x + bend, H - h); ctx.strokeStyle = css(mix(c.form, c.deep, 0.5 + 0.3 * Math.sin(i)), 0.9 * a); ctx.lineWidth = 0.006; ctx.stroke(); }
      }
      if (s.id === 'wind-trees') FG.forest(ctx, { ...s, birds: [] }, c, H, t, a * 0.9, true);
    },
    forest(ctx, s, c, H, t, a, onlyCanopy) {
      s.crowns.forEach((row, i) => {
        const k = (i + 1) / 3, base = H * (0.62 + i * 0.13), sway = 0.006 * Math.sin(t * 0.5 + i);
        ctx.beginPath(); ctx.moveTo(-0.1, H + 0.1);
        row.forEach((cr) => { ctx.arc(cr.x + sway * (1 + Math.sin(cr.ph)), base + cr.dy * H, cr.r * 0.6, Math.PI, 0); });
        ctx.lineTo(1.1, H + 0.1); ctx.closePath();
        ctx.fillStyle = css(mix(mix(c.form, c.light, 0.25 * (1 - k)), c.deep, 0.55 * k), 0.92 * a); ctx.fill();
      });
      if (onlyCanopy) return;
      ctx.lineCap = 'round'; ctx.lineWidth = 0.004; ctx.strokeStyle = css(c.deep, 0.8 * a);
      for (const b of s.birds) { const x = ((b.x + t * b.v) % 1.2) - 0.1, y = b.y * H + 0.01 * Math.sin(t + b.ph), f = 0.5 + 0.5 * Math.sin(t * 3 + b.ph); ctx.beginPath(); ctx.moveTo(x - b.s, y - b.s * 0.4 * f); ctx.quadraticCurveTo(x - b.s * 0.4, y - b.s * 0.5, x, y); ctx.quadraticCurveTo(x + b.s * 0.4, y - b.s * 0.5, x + b.s, y - b.s * 0.4 * f); ctx.stroke(); }
      if (s.id === 'forest-brook') FG.flow(ctx, { ...s, id: 'river', ribbons: s.ribbons.slice(4) }, c, H, t, a * 0.8);
    },
    fire(ctx, s, c, H, t, a) {
      const stove = s.id === 'fire-stove' && a > 0.5, cx = 0.5, by = H * (stove ? 0.78 : 0.86), fl = hn(t, 1);
      radial(ctx, cx, by, 0.55, c.accent, (0.35 + 0.15 * fl) * a);
      s.flames.forEach((f, i) => {
        const sw = 0.025 * Math.sin(t * 1.8 + f.ph), h = f.h * H * (0.85 + 0.25 * hn(t * 1.3, i)), x = cx + f.x, w = f.w;
        [[mix(c.accent, c.form, 0.35), 1], [c.accent, 0.62], [mix(c.accent, c.light, 0.6), 0.3]].forEach(([col, k]) => {
          ctx.beginPath(); ctx.moveTo(x - w * k, by); ctx.bezierCurveTo(x - w * k, by - h * k * 0.5, x + sw - w * k * 0.4, by - h * k * 0.8, x + sw * 1.5, by - h * k); ctx.bezierCurveTo(x + sw + w * k * 0.4, by - h * k * 0.8, x + w * k, by - h * k * 0.5, x + w * k, by); ctx.closePath();
          ctx.fillStyle = css(col, 0.75 * a); ctx.fill();
        });
      });
      for (const p of s.dots.slice(0, 18)) { const u = (p.y + t * p.sp * 0.12) % 1, x = cx + (p.x - 0.5) * 0.4 + 0.03 * Math.sin(t + p.ph), y = by - u * H * 0.8; C.circle(ctx, x, y, p.r * 0.8); ctx.fillStyle = css(mix(c.accent, c.light, 0.5), (1 - u) * a); ctx.fill(); }
      ctx.fillStyle = css(c.deep, 0.9 * a); ctx.fillRect(0.2, by, 0.6, 0.025);
      if (stove) { ctx.strokeStyle = css(c.deep, 0.95); ctx.lineWidth = 0.09; ctx.beginPath(); ctx.roundRect(0.14, H * 0.18, 0.72, H * 0.72, 0.08); ctx.stroke(); ctx.strokeStyle = css(c.light, 0.12); ctx.lineWidth = 0.006; ctx.beginPath(); ctx.roundRect(0.19, H * 0.23, 0.62, H * 0.62, 0.05); ctx.stroke(); }
    },
    room(ctx, s, c, H, t, a) {
      const train = s.id === 'train', n = s.id === 'cafe' ? 18 : s.id === 'room-house' ? 7 : 12;
      if (s.id === 'room-house' && a > 0.6) { ctx.fillStyle = css(mix(c.accent, c.tile, 0.4), 0.12); ctx.fillRect(0.58, H * 0.15, 0.28, H * 0.42); ctx.strokeStyle = css(c.light, 0.18); ctx.lineWidth = 0.006; ctx.strokeRect(0.58, H * 0.15, 0.28, H * 0.42); ctx.beginPath(); ctx.moveTo(0.72, H * 0.15); ctx.lineTo(0.72, H * 0.57); ctx.stroke(); }
      s.bokeh.slice(0, n).forEach((b, i) => {
        let x = b.x + 0.02 * Math.sin(t * 0.2 + b.ph), y = b.y * H + 0.01 * Math.cos(t * 0.17 + b.ph);
        if (train) { x = ((b.x + t * 0.05 * (1 + i % 3)) % 1.3) - 0.15; y = H * (0.3 + 0.25 * (b.y - 0.5)); }
        if (train) { ctx.lineCap = 'round'; ctx.strokeStyle = css(c[b.role === 'form' ? 'accent' : b.role], b.a * 0.6 * a); ctx.lineWidth = b.r * 0.35; ctx.beginPath(); ctx.moveTo(x - 0.12, y); ctx.lineTo(x, y); ctx.stroke(); }
        else radial(ctx, x, y, b.r, c[b.role], b.a * a * (0.8 + 0.2 * Math.sin(t * 0.5 + b.ph)));
      });
    },
    night(ctx, s, c, H, t, a) {
      for (const p of s.dots) { const tw = 0.5 + 0.5 * Math.sin(t * p.sp + p.ph); C.circle(ctx, p.x, p.y * H * 0.62, p.r * 1.1); ctx.fillStyle = css(c.light, p.a * (0.35 + 0.65 * tw) * a); ctx.fill(); }
      if (a < 0.6) return;
      if (s.id === 'night-meadow') { ctx.beginPath(); ctx.moveTo(0, H); for (let x = 0; x <= 1.001; x += 0.01) ctx.lineTo(x, H * (0.8 + 0.03 * Math.sin(x * 9) + (x * 97 % 1) * 0.04)); ctx.lineTo(1, H); ctx.fillStyle = css(c.deep, 0.95); ctx.fill(); }
      if (s.id === 'night-frogs') { ctx.beginPath(); ctx.ellipse(0.5, H * 0.84, 0.42, H * 0.1, 0, 0, TAU); ctx.fillStyle = css(mix(dark(c, 0.3), c.accent, 0.1), 0.9); ctx.fill(); C.circle(ctx, 0.62, H * 0.84, 0.025); ctx.fillStyle = css(c.light, 0.5); ctx.fill(); }
      if (s.id === 'night-insects') for (const p of s.dots.slice(0, 9)) { const x = p.x + 0.04 * Math.sin(t * 0.4 * p.sp + p.ph), y = H * (0.55 + 0.35 * p.y) + 0.03 * Math.cos(t * 0.3 + p.ph); radial(ctx, x, y, 0.03, c.accent, 0.6 * (0.5 + 0.5 * Math.sin(t * 1.5 * p.sp + p.ph))); }
    },
    noise(ctx, s, c, H, t, a) {
      const coarse = s.id === 'noise-brown' ? 2 : s.id === 'noise-pink' ? 1.5 : 1;
      ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = (s.id === 'noise-white' ? 0.45 : 0.32) * a;
      const p = C.pattern(ctx, grainTex(), 256 / coarse, 1); p.setTransform(new DOMMatrix().translate(Math.floor(t * 7) * 0.37 % 1, Math.floor(t * 7) * 0.61 % 1).scale(coarse / 256));
      ctx.fillStyle = p; ctx.fillRect(0, 0, 1, H); ctx.restore();
      for (let i = 0; i < 10; i++) { const y = H * (0.1 + i * 0.085); ctx.fillStyle = css(c.light, (0.03 + 0.03 * Math.sin(i * 1.9 + t * 0.2)) * a); ctx.fillRect(0, y, 1, H * 0.035); }
    },
    drone(ctx, s, c, H, t, a) {
      const cy = H * 0.5;
      for (let i = 0; i < 6; i++) { const u = ((t / 14 + i / 6) % 1), R = 0.06 + u * 0.6; ctx.beginPath(); ctx.ellipse(0.5, cy, R, R * 0.8, 0, 0, TAU); ctx.strokeStyle = css(mix(c.accent, c.light, 0.3), Math.sin(Math.PI * u) * 0.5 * a); ctx.lineWidth = 0.01 * (1 - u) + 0.002; ctx.stroke(); }
      radial(ctx, 0.5, cy, 0.18 * (1 + 0.06 * Math.sin(t * 0.6)), c.accent, 0.6 * a);
    },
    binaural(ctx, s, c, H, t, a) {
      const band = (y0, f, col, ph) => { ctx.beginPath(); for (let x = 0; x <= 1.001; x += 0.01) { const y = y0 + H * 0.06 * Math.sin(TAU * f * x + ph); x ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } ctx.strokeStyle = css(col, 0.7 * a); ctx.lineWidth = 0.008; ctx.stroke(); };
      band(H * 0.32, 5, c.form === c.deep ? c.accent : mix(c.form, c.light, 0.35), t * 0.9); band(H * 0.68, 5.6, c.accent, t * 0.9);
      ctx.beginPath(); for (let x = 0; x <= 1.001; x += 0.005) { const env = Math.abs(Math.cos(Math.PI * 0.6 * x - t * 0.3)), y = H * 0.5 + H * 0.12 * env * Math.sin(TAU * 5.3 * x + t * 0.9); x ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      ctx.strokeStyle = css(c.light, 0.55 * a); ctx.lineWidth = 0.005; ctx.stroke();
    },
  };
  let grainCv = null;
  function grainTex() { if (grainCv) return grainCv; const N = 128, cv = document.createElement('canvas'); cv.width = cv.height = N; const g = cv.getContext('2d'), img = g.createImageData(N, N), r = C.makeRng('grain'); for (let i = 0; i < img.data.length; i += 4) { const v = r.next() * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; } g.putImageData(img, 0, 0); return (grainCv = cv); }
  // Darken the foot of every card so a light title reads on it.
  function scrim(ctx, c, H) { const g = ctx.createLinearGradient(0, H * 0.45, 0, H); g.addColorStop(0, css(c.deep, 0)); g.addColorStop(1, css(c.deep, 0.6)); ctx.fillStyle = g; ctx.fillRect(0, H * 0.45, 1, H * 0.55); }

  const scenes = new Map();
  const sceneOf = (id) => { if (!scenes.has(id)) scenes.set(id, buildSound(id)); return scenes.get(id); };
  function drawSound(ctx, id, pal, t, o = {}) {
    const H = o.H || 1, c = C.roles(pal), s = sceneOf(id);
    BG[s.kind](ctx, s, c, H); FG[s.kind](ctx, s, c, H, t, 1); scrim(ctx, c, H);
    C.finish(ctx, c, o.px || 256, { dpr: o.dpr, speckle: 0.12, vignette: 0.12 });
  }
  // A preset paints its loudest layer's field, then every layer's elements,
  // each as strong as its volume.
  function drawPreset(ctx, preset, pal, t, o = {}) {
    const H = o.H || 1, c = C.roles(pal), layers = preset.layers.map(([id, v]) => [sceneOf(id), v]).sort((a, b) => b[1] - a[1]);
    BG[layers[0][0].kind](ctx, layers[0][0], c, H);
    const order = layers.slice().sort((a, b) => (a[0].kind === 'rain' || a[0].kind === 'wind') - (b[0].kind === 'rain' || b[0].kind === 'wind'));
    for (const [s, v] of order) FG[s.kind](ctx, s, c, H, t, clamp(v * 1.4, 0.35, 1));
    scrim(ctx, c, H);
    C.finish(ctx, c, o.px || 256, { dpr: o.dpr, speckle: 0.12, vignette: 0.12 });
  }

  // ---------- covers ----------
  const COVER_TITLES = {
    course: ['Practising the Jhānas', 'The Loving Kindness Retreat', 'Qualia Mastery', 'Seeing That Frees', 'Insight Retreat 2019', 'Metta for Beginners', 'Spring at Gaia House', 'The Heart of Awareness', 'Ten Days of Silence', 'Breath and Body', 'Working with Emotions', 'Winter Retreat'],
    playlist: ['Morning sits', 'Before sleep', 'Jhāna talks', 'Walking', 'Metta', 'Favourites', 'Short sits', 'Questions and answers', 'Body scans', 'For hard days', 'Sangha talks', 'Silence'],
    teacher: ['Rob Burbea', 'Leigh Brasington', 'Ajahn Sucitto', 'Tara Brach', 'Gil Fronsdal', 'Joseph Goldstein', 'Sharon Salzberg', 'Christina Feldman', 'Martine Batchelor', 'Kittisaro', 'Ruth King', 'Catherine McGee'],
    single: ['Guided body scan', 'Settling the breath', 'On equanimity', 'Open awareness', 'Walking meditation', 'Forgiveness practice', 'Noting practice', 'Sitting with pain', 'Gratitude', 'The five hindrances', 'Kindness for oneself', 'Resting as awareness'],
  };
  // A cover is painted once: two ink plates (one misregistered), cut edges,
  // then paper and speckle. id → the same cover every time.
  function drawCover(ctx, kind, id, pal, o = {}) {
    const r = C.makeRng(kind + ':' + id), c = C.roles(pal);
    const inks = [c.form, c.accent, c.stroke, mix(c.form, c.accent, 0.5), mix(c.form, c.tile, 0.45)];
    const mis = [r.range(-0.012, 0.012), r.range(0.004, 0.012)];
    const plateB = (fn) => { ctx.save(); ctx.translate(mis[0], mis[1]); ctx.globalCompositeOperation = C.overprint(c); fn(); ctx.restore(); };
    const paperTint = mix(c.tile, r.pick([c.accent, c.form, c.tile]), r.range(0.05, 0.18));
    ctx.fillStyle = css(paperTint); ctx.fillRect(0, 0, 1, 1);
    if (kind === 'course') {
      // A place under one of four lights; the hills take a ramp that suits it.
      const key = r.pick(['day', 'dusk', 'night', 'mist']), sub = r.pick(['hills', 'lake', 'door', 'path', 'hills', 'trees']), hy = r.range(0.48, 0.68);
      const skyCol = { day: mix(paperTint, c.accent, 0.12), dusk: mix(c.accent, c.form, r.range(0.2, 0.6)), night: mix(c.deep, c.form, r.range(0.1, 0.3)), mist: mix(c.tile, c.form, 0.12) }[key];
      const near = key === 'night' ? mix(c.deep, c.tile, 0.05) : key === 'mist' ? mix(c.form, c.tile, 0.2) : r.pick([c.deep, mix(c.stroke, c.form, 0.4), mix(c.form, c.deep, 0.5)]);
      const far = key === 'night' ? mix(c.deep, c.form, 0.35) : key === 'mist' ? mix(c.tile, c.form, 0.45) : r.pick([mix(c.form, c.tile, 0.35), mix(c.accent, c.tile, 0.3), c.form]);
      ctx.fillStyle = css(skyCol); ctx.fillRect(0, 0, 1, 1);
      if (key === 'night') { for (let i = 0; i < 30; i++) { C.circle(ctx, r.next(), r.next() * hy, r.range(0.002, 0.005)); ctx.fillStyle = css(c.light, r.range(0.3, 0.9)); ctx.fill(); } }
      const sun = C.makeBlob(r, r.range(0.22, 0.78), r.range(0.2, Math.max(0.24, hy - 0.12)), r.range(0.07, 0.15), 0.6, 0.004);
      const sunCol = key === 'night' ? mix(c.light, c.accent, 0.15) : key === 'mist' ? mix(c.tile, c.accent, 0.5) : key === 'dusk' ? mix(c.accent, c.light, 0.35) : r.pick([c.accent, c.form]);
      const sunFill = () => { C.blobPath(ctx, sun); ctx.fillStyle = css(sunCol); ctx.fill(); };
      if (key === 'night') sunFill(); else if (key !== 'mist' || r.chance(0.6)) plateB(sunFill);
      const n = sub === 'lake' ? 1 : r.int(2, 4);
      for (let i = 0; i < n; i++) {
        const k = n === 1 ? 1 : i / (n - 1), base = hy + i * r.range(0.07, 0.12), pts = [[-0.05, 1.05]];
        const f = r.range(0.5, 1.8), ph = r.range(0, TAU), amp = r.range(0.03, 0.12) * (sub === 'lake' ? 0.15 : 1);
        for (let x = -0.05; x <= 1.05; x += 0.05) pts.push([x, base - amp * (0.6 + 0.4 * Math.sin(TAU * f * x + ph))]);
        pts.push([1.05, 1.05]);
        C.cutPoly(ctx, pts, r, 0.004); ctx.fillStyle = css(mix(far, near, k)); ctx.fill();
        if (key === 'mist' && i < n - 1) { const g = ctx.createLinearGradient(0, base - 0.08, 0, base + 0.04); g.addColorStop(0, css(c.tile, 0)); g.addColorStop(1, css(c.tile, 0.55)); ctx.fillStyle = g; ctx.fillRect(0, base - 0.08, 1, 0.12); }
      }
      if (sub === 'lake') { ctx.lineCap = 'round'; for (let i = 0; i < 4; i++) { const y = hy + 0.05 + i * 0.07, w = (sun.R * 2) * (0.9 - i * 0.18); ctx.strokeStyle = css(sunCol, 0.8 - i * 0.15); ctx.lineWidth = 0.02; ctx.beginPath(); ctx.moveTo(sun.cx - w / 2, y); ctx.lineTo(sun.cx + w / 2, y); ctx.stroke(); } }
      if (sub === 'door') { const w = r.range(0.11, 0.15), x = r.range(0.3, 0.7), b = hy + 0.03, tp = b - r.range(0.2, 0.28); C.cutPoly(ctx, [[x - w / 2, b], [x - w / 2, tp + w / 2], ...Array.from({ length: 9 }, (_, i) => [x - (w / 2) * Math.cos((i / 8) * Math.PI), tp + w / 2 - (w / 2) * Math.sin((i / 8) * Math.PI)]), [x + w / 2, b]], r, 0.003); ctx.fillStyle = css(key === 'night' ? c.accent : c.stroke); ctx.fill(); }
      if (sub === 'path') { ctx.beginPath(); ctx.moveTo(0.42, 1.02); ctx.bezierCurveTo(0.7, 0.86, 0.3, 0.78, 0.52, hy + 0.06); ctx.lineTo(0.55, hy + 0.06); ctx.bezierCurveTo(0.4, 0.8, 0.86, 0.86, 0.66, 1.02); ctx.closePath(); ctx.fillStyle = css(mix(c.tile, c.accent, 0.3), 0.9); ctx.fill(); }
      if (sub === 'trees') { for (let i = 0; i < r.int(3, 6); i++) { const x = r.range(0.08, 0.92), b = hy + r.range(0.02, 0.1), h = r.range(0.12, 0.24), w = h * 0.32; C.cutPoly(ctx, [[x, b - h], [x + w, b], [x - w, b]], r, 0.003); ctx.fillStyle = css(mix(near, c.deep, 0.3)); ctx.fill(); } }
    } else if (kind === 'playlist') {
      const n = r.int(3, 5);
      for (let i = 0; i < n; i++) {
        const shape = r.pick(['card', 'card', 'disc', 'half', 'strip']), x = r.range(0.25, 0.75), y = r.range(0.25, 0.75), s = r.range(0.22, 0.42), rot = r.range(-0.3, 0.3), col = inks[(i + r.int(0, 4)) % inks.length];
        const draw = () => {
          ctx.save(); ctx.translate(x, y); ctx.rotate(rot);
          if (shape === 'card') C.cutPoly(ctx, [[-s / 2, -s * 0.65], [s / 2, -s * 0.65], [s / 2, s * 0.65], [-s / 2, s * 0.65]], r, 0.003);
          else if (shape === 'strip') C.cutPoly(ctx, [[-s, -0.03], [s, -0.03], [s, 0.03], [-s, 0.03]], r, 0.002);
          else if (shape === 'half') C.cutPoly(ctx, Array.from({ length: 13 }, (_, j) => [s * 0.6 * Math.cos(Math.PI + (j / 12) * Math.PI), s * 0.6 * Math.sin(Math.PI + (j / 12) * Math.PI)]), r, 0.003);
          else C.blobPath(ctx, C.makeBlob(r, 0, 0, s * 0.5, 0.4, 0.004));
          ctx.fillStyle = css(col); ctx.fill(); ctx.restore();
        };
        if (i % 2) plateB(draw); else draw();
      }
    } else if (kind === 'teacher') {
      const warm = mix(c.accent, c.form, r.range(0.2, 0.7)), hx = 0.5 + r.range(-0.06, 0.06), hy = r.range(0.36, 0.42), hr = r.range(0.15, 0.18);
      plateB(() => { C.blobPath(ctx, C.makeBlob(r, 0.5 + r.range(-0.15, 0.15), r.range(0.3, 0.5), r.range(0.26, 0.36), 0.6, 0.004)); ctx.fillStyle = css(mix(warm, c.tile, 0.45)); ctx.fill(); });
      const sh = r.range(0.28, 0.36), top = hy + hr * 0.85;
      C.cutPoly(ctx, [[hx - sh, 1.05], [hx - sh, top + 0.16], ...Array.from({ length: 11 }, (_, i) => [hx - sh * Math.cos((i / 10) * Math.PI), top + 0.16 - 0.16 * Math.sin((i / 10) * Math.PI)]), [hx + sh, 1.05]], r, 0.004);
      ctx.fillStyle = css(r.pick([c.stroke, mix(c.stroke, c.form, 0.3), c.form])); ctx.fill();
      const head = C.makeBlob(r, hx, hy, hr, 0.7, 0.003); head.asp = r.range(0.82, 0.92); head.rot = Math.PI / 2 + r.range(-0.15, 0.15);
      plateB(() => { C.blobPath(ctx, head); ctx.fillStyle = css(warm); ctx.fill(); });
      if (r.chance(0.4)) { ctx.strokeStyle = css(c.accent, 0.8); ctx.lineWidth = 0.012; ctx.beginPath(); ctx.arc(hx, hy, hr * 1.5, Math.PI * 1.1, Math.PI * 1.95); ctx.stroke(); }
    } else {
      const motif = r.pick(['disc', 'arch', 'drop', 'leaf', 'crescent']), col = r.pick([c.form, c.accent, c.form, mix(c.form, c.accent, 0.5), c.stroke]), x = 0.5 + r.range(-0.1, 0.1), y = r.range(0.4, 0.52), s = r.range(0.18, 0.26);
      ctx.strokeStyle = css(c.stroke, 0.7); ctx.lineWidth = 0.008; ctx.beginPath(); ctx.moveTo(0.12, r.range(0.7, 0.8)); ctx.lineTo(0.88, r.range(0.7, 0.8)); ctx.stroke();
      plateB(() => {
        if (motif === 'disc' || motif === 'crescent') { C.blobPath(ctx, C.makeBlob(r, x, y, s, 0.5, 0.004)); ctx.fillStyle = css(col); ctx.fill(); if (motif === 'crescent') { ctx.globalCompositeOperation = 'source-over'; C.circle(ctx, x + s * 0.45, y - s * 0.3, s * 0.9); ctx.fillStyle = css(paperTint); ctx.fill(); } }
        else if (motif === 'arch') { C.cutPoly(ctx, [[x - s * 0.7, y + s * 1.1], [x - s * 0.7, y], ...Array.from({ length: 11 }, (_, i) => [x - s * 0.7 * Math.cos((i / 10) * Math.PI), y - s * 0.7 * Math.sin((i / 10) * Math.PI)]), [x + s * 0.7, y + s * 1.1]], r, 0.004); ctx.fillStyle = css(col); ctx.fill(); }
        else { ctx.beginPath(); const a = motif === 'leaf' ? 0.9 : 1.9; ctx.moveTo(x, y - s * a); ctx.bezierCurveTo(x + s, y - s * 0.3, x + s * 0.8, y + s, x, y + s); ctx.bezierCurveTo(x - s * 0.8, y + s, x - s, y - s * 0.3, x, y - s * a); ctx.fillStyle = css(col); ctx.fill(); }
      });
    }
    C.finish(ctx, c, o.px || 256, { dpr: o.dpr, paper: 0.2, speckle: 0.4, vignette: 0.06 });
  }

  return { SOUNDS, PRESETS, COVER_TITLES, drawSound, drawPreset, drawCover, KIND };
})();
