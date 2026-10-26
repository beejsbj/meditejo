/* Round 3 composition grammar.
 *
 *   card   = paper + ground? + figure + accent?
 *   paper  = light | mid | dark, weighted by kind
 *   ground = a primitive that fills the card, quiet (low contrast)
 *   figure = one primitive, placed by a layout (centre, low, left, right, big)
 *   accent = a small primitive on the second ink plate, misregistered
 *
 * A meaning map says which primitives may fill each slot for a sound kind or
 * cover kind. The seed picks the structure first, then the parameters, so two
 * rain cards can differ in what they are made of, not only in colour. */
const Compose = (() => {
  'use strict';
  const C = Core, { mix, css, lerp } = C;

  // ---------- meaning ----------
  // slot lists may repeat a name to weight it; null means "leave empty".
  const M = {
    rain: { paper: { dark: 3, mid: 2 }, ground: ['streaks', 'streaks', 'streaks', 'strata', 'waves'], figure: ['rings', 'streaks', 'rings', 'horizon', 'moon', 'threads'], accent: ['disc', 'points', null, null] },
    water: { paper: { mid: 3, dark: 2, light: 1 }, ground: ['waves', 'scales', 'strata', null], figure: ['rings', 'waves', 'scales', 'horizon', 'rings'], accent: ['disc', 'moon', null] },
    wind: { paper: { mid: 3, light: 2 }, ground: ['threads', 'threads', 'hills', null], figure: ['threads', 'threads', 'grove', 'breath'], accent: ['disc', 'points', null] },
    forest: { paper: { mid: 2, light: 2, dark: 1 }, ground: ['grove', 'hills', 'points', null], figure: ['grove', 'lotus', 'mandala', 'hills'], accent: ['disc', 'sun', 'points', null] },
    fire: { paper: { dark: 4, mid: 1 }, ground: ['dots', 'strata', null, null], figure: ['fire', 'fire', 'sun'], accent: ['points', 'disc', null] },
    room: { paper: { dark: 2, mid: 2, light: 1 }, ground: ['dots', 'weave', 'strata', null], figure: ['dots', 'weave', 'breath', 'stack', 'sun'], accent: ['disc', 'moon', null] },
    night: { paper: { dark: 4 }, ground: ['points', 'points', 'dots', null], figure: ['moon', 'points', 'rings', 'grove', 'lotus', 'moon'], accent: ['disc', 'points', null] },
    noise: { paper: { light: 1, mid: 2, dark: 2 }, ground: ['dots', 'strata', 'dots'], figure: ['dots', 'strata', 'weave'], accent: [null, null, 'disc'] },
    drone: { paper: { dark: 3, mid: 1 }, ground: ['rings', null], figure: ['rings', 'mandala', 'breath', 'spiral'], accent: ['disc', null] },
    binaural: { paper: { dark: 2, mid: 2 }, ground: ['waves', null], figure: ['rings', 'waves'], accent: ['disc', null], force: { figure: { kind: 'interference' } } },
    course: { paper: { light: 4, mid: 2, dark: 1 }, ground: ['hills', 'horizon', 'strata', 'points', null, null], figure: ['sun', 'mandala', 'cairn', 'lotus', 'horizon', 'spiral', 'grove', 'moon', 'rings', 'sun'], accent: ['disc', 'moon', 'disc', null, null, 'points'] },
    playlist: { paper: { light: 3, mid: 2, dark: 1 }, ground: ['weave', 'dots', 'strata', 'scales', null], figure: ['stack', 'stack', 'weave', 'moon', 'dots', 'cairn'], accent: ['disc', null, null] },
    teacher: { paper: { light: 3, mid: 2 }, ground: [null, null, 'rings', 'dots'], figure: ['mandala', 'mandala', 'lotus', 'breath', 'sun'], accent: [null, null, 'disc'], layout: ['centre', 'big'] },
    single: { paper: { light: 3, mid: 1, dark: 1 }, ground: [null], figure: Object.keys(Prims).filter((k) => !['stack'].includes(k)), accent: [null] },
  };
  const SOUND_KIND = (id) => id.startsWith('rain') ? 'rain' : ['stream', 'river', 'waves', 'sea'].includes(id) ? 'water' : id.startsWith('wind') ? 'wind'
    : ['forest-birds', 'dawn-chorus', 'evening-birds', 'forest-brook'].includes(id) ? 'forest' : id.startsWith('fire') ? 'fire' : ['room-house', 'cafe', 'train'].includes(id) ? 'room'
    : id.startsWith('night') ? 'night' : id.startsWith('noise') ? 'noise' : id;

  const LAYOUT = {
    centre: () => ({ cx: 0.5, cy: 0.48, s: 0.3 }),
    low: () => ({ cx: 0.5, cy: 0.58, s: 0.26 }),
    left: () => ({ cx: 0.36, cy: 0.46, s: 0.25 }),
    right: () => ({ cx: 0.64, cy: 0.46, s: 0.25 }),
    big: () => ({ cx: 0.5, cy: 0.52, s: 0.4 }),
  };
  const ACCENT_AT = (fig, r) => { const a = r.range(0, Math.PI * 2), d = fig.s * r.range(1.05, 1.4); return { cx: C.clamp(fig.cx + Math.cos(a) * d, 0.14, 0.86), cy: C.clamp(fig.cy + Math.sin(a) * d * 0.8 - 0.05, 0.14, 0.7), s: r.range(0.05, 0.09) }; };

  // ---------- inks ----------
  // Paper sets the value key; inks are chosen to read against it.
  function inks(c, key, r) {
    const paper = key === 'light' ? mix(c.tile, c.accent, r.range(0, 0.12)) : key === 'mid' ? mix(c.form, c.tile, r.range(0.25, 0.45)) : mix(c.deep, c.form, r.range(0.12, 0.3));
    const strong = C.lum(paper) > 0.3 ? [c.stroke, mix(c.stroke, c.form, 0.35), c.deep].filter((x) => C.contrast(x, paper) > 2) : [c.light, mix(c.light, c.accent, 0.3)];
    const warm = [c.accent, mix(c.accent, c.form, 0.3)];
    const main = r.pick([c.form, ...strong, warm[0]].filter((x) => C.contrast(x, paper) > 1.35)) || strong[0];
    const alt = r.pick(warm.filter((x) => C.hex(x) !== C.hex(main)).concat([mix(main, paper, 0.4)]));
    return {
      paper, main, alt,
      line: C.lum(paper) > 0.3 ? mix(c.stroke, paper, 0.25) : mix(c.light, paper, 0.25),
      glow: mix(c.accent, c.light, 0.45),
      ground: { paper, main: mix(paper, main, 0.45), alt: mix(paper, alt, 0.45), line: mix(paper, C.lum(paper) > 0.3 ? c.stroke : c.light, 0.5), glow: mix(paper, c.accent, 0.5) },
    };
  }

  // ---------- build ----------
  // Returns a plain description: paper key, inks seed, layers with their
  // primitive, slot and built parameters. Nothing here draws.
  function build(kindKey, id, opts = {}) {
    const m = M[kindKey], r = C.makeRng(`r3:${kindKey}:${id}`);
    const key = r.weighted(m.paper);
    const layoutName = r.pick(m.layout || ['centre', 'centre', 'low', 'left', 'right', 'big']);
    const fig = LAYOUT[layoutName]();
    const layers = [];
    const g = opts.ground !== undefined ? opts.ground : r.pick(m.ground);
    const f = opts.figure || r.pick(m.figure);
    let a = opts.accent !== undefined ? opts.accent : r.pick(m.accent);
    if (g && g !== f) layers.push({ prim: g, slot: 'ground', p: Prims[g].build(C.makeRng(`${id}:g`), { cx: 0.5, cy: 0.5, s: 0.5 }, 'ground') });
    const fp = Prims[f].build(C.makeRng(`${id}:f`), fig, 'figure');
    Object.assign(fp, (m.force && m.force.figure) || {});
    layers.push({ prim: f, slot: 'figure', p: fp });
    if (a && a !== f) layers.push({ prim: a, slot: 'accent', p: Prims[a].build(C.makeRng(`${id}:a`), ACCENT_AT(fig, r), 'accent') });
    return { kindKey, id, key, layoutName, layers, inkSeed: `${id}:ink`, mis: [r.range(-0.01, 0.01), r.range(0.003, 0.01)] };
  }

  // ---------- print finish, baked ----------
  // Round 2 laid paper grain with an 'overlay' pattern fill and speckle with a
  // second pattern on every frame; on a page of live cards that fill cost
  // more than the art. Here grain (light and dark flecks), ink speckle in the
  // paper colour and a faint vignette are baked once per paper colour and
  // size into one transparent raster, and each frame draws it with one
  // drawImage.
  const grains = new Map();
  let paperPx = null;
  function grainFor(c, px, H = 1) {
    const ph = Math.round(px * H), key = `${C.hex(c.tile)}|${px}|${ph}`;
    if (grains.has(key)) return grains.get(key);
    const cv = document.createElement('canvas'); cv.width = px; cv.height = ph;
    const g = cv.getContext('2d'), img = g.createImageData(px, ph), d = img.data, r = C.makeRng('grain3'), tile = C.rgb(c.tile), deep = C.rgb(c.deep);
    const light = C.lum(c.tile) > 0.35;
    // Round 2's paper (clouding, tooth, fibres), read once and tiled.
    paperPx = paperPx || C.paperTex().getContext('2d').getImageData(0, 0, 256, 256).data;
    for (let y = 0; y < ph; y++) for (let x = 0; x < px; x++) {
      const i = (y * px + x) * 4, dx = x / px - 0.5, dy = (y / ph - 0.5) * H, vig = Math.max(0, Math.hypot(dx, dy) - 0.38) / 0.4;
      if (r.next() < 0.005) { d[i] = tile[0]; d[i + 1] = tile[1]; d[i + 2] = tile[2]; d[i + 3] = 120; continue; }
      const v = (paperPx[((y & 255) * 256 + (x & 255)) * 4] - 128) / 128;
      if (v > 0) { d[i] = d[i + 1] = d[i + 2] = 255; d[i + 3] = v * (light ? 40 : 22); }
      else { d[i] = deep[0]; d[i + 1] = deep[1]; d[i + 2] = deep[2]; d[i + 3] = -v * (light ? 34 : 40) + vig * 28; }
    }
    g.putImageData(img, 0, 0);
    if (grains.size > 24) grains.delete(grains.keys().next().value);
    grains.set(key, cv);
    return cv;
  }

  // ---------- draw ----------
  // upto: draw only the first n layers (for the grammar walkthrough).
  function draw(ctx, comp, pal, t, o = {}) {
    const c = C.roles(pal), k = inks(c, comp.key, C.makeRng(comp.inkSeed)), still = !!o.still, n = o.upto ?? comp.layers.length;
    ctx.fillStyle = css(k.paper); ctx.fillRect(0, 0, 1, o.H || 1);
    comp.layers.slice(0, n).forEach((L) => {
      const kk = L.slot === 'ground' ? { ...k.ground, paper: k.paper } : L.slot === 'accent' ? { ...k, main: k.alt, alt: k.main } : k;
      ctx.save();
      if (L.slot === 'accent') { ctx.translate(comp.mis[0], comp.mis[1]); ctx.globalCompositeOperation = C.lum(k.paper) > 0.3 ? 'multiply' : 'screen'; }
      Prims[L.prim].draw(ctx, L.p, kk, t, still);
      ctx.restore();
    });
    if (o.scrim) { const g = ctx.createLinearGradient(0, 0.5, 0, 1); g.addColorStop(0, css(c.deep, 0)); g.addColorStop(1, css(c.deep, 0.62)); ctx.fillStyle = g; ctx.fillRect(0, 0.5, 1, 0.5); }
    ctx.drawImage(grainFor(c, o.px || 256, o.H || 1), 0, 0, 1, o.H || 1);
  }

  // A preset: the loudest layer's ground and figure, then each quieter
  // layer's figure as an accent, on the second plate.
  function buildPreset(preset) {
    const sorted = preset.layers.slice().sort((a, b) => b[1] - a[1]);
    const base = build(SOUND_KIND(sorted[0][0]), sorted[0][0]);
    const extra = sorted.slice(1).map(([id], i) => {
      const sub = build(SOUND_KIND(id), id), fl = sub.layers.find((l) => l.slot === 'figure');
      const pl = i === 0 ? { cx: 0.76, cy: 0.3, s: 0.14 } : { cx: 0.24, cy: 0.26, s: 0.11 };
      return { prim: fl.prim, slot: 'accent', p: Prims[fl.prim].build(C.makeRng(`${preset.id}:${id}`), pl, 'accent') };
    });
    return { ...base, id: preset.id, layers: base.layers.filter((l) => l.slot !== 'accent').concat(extra) };
  }

  return { M, SOUND_KIND, build, draw, buildPreset, LAYOUT };
})();
