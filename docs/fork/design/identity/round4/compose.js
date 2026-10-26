/* Round 4 composition: a tight meaning map, a seeded builder, candidates for
 * curation, and a frozen form for what ships.
 *
 *   card = ground (an atmosphere or paper) + figure? + accent?
 *
 * The meaning map lists, for each class, the only grounds, figures and
 * accents allowed. "rings:ripple" pins a primitive's variant. Items we ship
 * are curated: a person picks one candidate and its frozen composition goes
 * in curated_art.json. Everything else (user-added, imported, created) is
 * built from its id by the same rules. */
const Compose = (() => {
  'use strict';
  const C = Core, { mix, css } = C;

  // ---------- the meaning map ----------
  const MAP = {
    rain: { label: 'Rain', grounds: ['rainfield', 'mist'], figures: ['streaks', 'rings:ripple', 'disc:halo'], accents: [null, null, 'disc:plain'] },
    stream: { label: 'Stream and river', grounds: ['mist', 'paper'], figures: ['waves', 'threads'], accents: [null] },
    brook: { label: 'Forest brook', grounds: ['canopy', 'mist'], figures: ['waves', 'threads'], accents: [null, 'flock'] },
    sea: { label: 'Sea', grounds: ['sea', 'dawn'], figures: ['disc:plain', 'flock', 'scales'], accents: [null, 'flock'] },
    wind: { label: 'Wind', grounds: ['mist', 'dawn'], figures: ['threads', 'grass'], accents: [null, 'flock'] },
    pines: { label: 'Wind in the pines', grounds: ['canopy', 'mist'], figures: ['threads'], accents: [null, 'flock'] },
    birds: { label: 'Birds', grounds: ['canopy', 'dawn'], figures: ['flock', 'petals'], accents: [null, 'disc:plain'] },
    fire: { label: 'Fire', grounds: ['hearth'], figures: ['fire:tongues', 'fire:embers'], accents: [null] },
    room: { label: 'Rooms', grounds: ['bokeh', 'paper'], figures: ['disc:halo', 'breath', 'rings:target'], accents: [null] },
    fan: { label: 'Fan', grounds: ['paper', 'mist'], figures: ['mandala', 'rings:target'], accents: [null] },
    train: { label: 'Trains', grounds: ['night', 'bokeh'], figures: ['threads', 'disc:halo'], accents: [null] },
    night: { label: 'Night', grounds: ['night'], figures: ['stars', 'moon'], accents: [null, 'stars'] },
    frogs: { label: 'Frogs by a pond', grounds: ['night'], figures: ['rings:ripple', 'moon', 'stars'], accents: [null, 'stars'] },
    nightshore: { label: 'Crickets by the sea', grounds: ['night'], figures: ['waves', 'moon', 'stars'], accents: [null, 'stars'] },
    meadow: { label: 'Meadow at night', grounds: ['night'], figures: ['grass', 'stars', 'moon'], accents: [null, 'stars'] },
    noise: { label: 'Noise colours', grounds: ['grain'], figures: [null], accents: [null] },
    drone: { label: 'Drone', grounds: ['night', 'mist'], figures: ['rings:target', 'mandala', 'breath'], accents: [null] },
    binaural: { label: 'Binaural', grounds: ['paper', 'night'], figures: ['rings:interference'], accents: [null] },
    course: { label: 'Courses', grounds: ['dawn', 'mist', 'paper'], figures: ['mandala', 'lotus', 'cairn', 'ammonite', 'disc:rayed', 'breath'], accents: [null, null, 'disc:plain', 'stars'] },
    single: { label: 'Singles', grounds: ['paper', 'mist'], figures: ['disc', 'breath', 'lotus', 'rings:ripple', 'ammonite'], accents: [null] },
    teacher: { label: 'Teachers', grounds: ['paper'], figures: ['mandala', 'lotus'], accents: [null] },
    playlist: { label: 'Playlists', grounds: ['paper', 'mist'], figures: ['cairn', 'scales', 'mandala', 'rings:target'], accents: [null] },
  };
  // Which class an id belongs to. Sounds first, then the cover kinds.
  function classOf(id, kind) {
    if (kind && kind !== 'sound' && kind !== 'preset') return kind;
    if (id.startsWith('rain')) return 'rain';
    if (id === 'stream' || id === 'river') return 'stream';
    if (id === 'forest-brook') return 'brook';
    if (['waves', 'sea', 'ocean'].includes(id)) return 'sea';
    if (id === 'wind-trees') return 'pines';
    if (id.startsWith('wind')) return 'wind';
    if (['forest-birds', 'dawn-chorus', 'evening-birds', 'wood-thrush'].includes(id)) return 'birds';
    if (id.startsWith('fire')) return 'fire';
    if (id === 'fan') return 'fan';
    if (id.startsWith('train')) return 'train';
    if (['room-house', 'cafe', 'laundry-room'].includes(id)) return 'room';
    if (id === 'night-frogs') return 'frogs';
    if (id === 'night-shore') return 'nightshore';
    if (id === 'night-meadow') return 'meadow';
    if (id.startsWith('night')) return 'night';
    if (id.startsWith('noise')) return 'noise';
    return id; // drone, binaural
  }

  // Where a figure sits; some figures have homes (fire low, birds high).
  const LAYOUT = {
    centre: { cx: 0.5, cy: 0.48, s: 0.3 }, big: { cx: 0.5, cy: 0.5, s: 0.38 }, low: { cx: 0.5, cy: 0.58, s: 0.27 },
    high: { cx: 0.5, cy: 0.34, s: 0.22 }, left: { cx: 0.36, cy: 0.44, s: 0.25 }, right: { cx: 0.64, cy: 0.44, s: 0.25 },
  };
  const HOME = { fire: ['low', 'centre'], grass: ['low', 'big'], lotus: ['low', 'centre'], cairn: ['low', 'centre'], flock: ['high', 'left', 'right'], moon: ['high', 'left', 'right'], disc: ['high', 'centre', 'left', 'right'], stars: ['centre', 'big'], petals: ['centre', 'big'], waves: ['low', 'centre'], streaks: ['centre', 'big'], threads: ['centre', 'big'] };
  const parse = (s) => (s ? { name: s.split(':')[0], kind: s.split(':')[1] } : null);

  // ---------- inks ----------
  function inks(c, tone, r) {
    const light = C.lum(tone) > 0.3;
    const strong = light ? [c.stroke, mix(c.stroke, c.form, 0.35), c.deep].filter((x) => C.contrast(x, tone) > 2) : [c.light, mix(c.light, c.accent, 0.3)];
    const main = r.pick([c.form, ...strong, c.accent].filter((x) => C.contrast(x, tone) > 1.4)) || strong[0];
    const alt = r.pick([c.accent, mix(c.accent, c.form, 0.3), mix(main, tone, 0.4)].filter((x) => C.hex(x) !== C.hex(main)));
    return { paper: tone, main, alt, line: light ? mix(c.stroke, tone, 0.25) : mix(c.light, tone, 0.25), glow: mix(c.accent, c.light, 0.45) };
  }

  // ---------- build ----------
  // seed is the whole identity of a composition: "rain-terrace#3".
  function build(cls, seed, extra = {}) {
    const m = MAP[cls], r = C.makeRng(`r4:${cls}:${seed}`);
    const gName = r.pick(m.grounds), f = parse(r.pick(m.figures)), a = parse(r.pick(m.accents));
    const gOpts = { ...(extra.ground || {}) };
    const comp = { cls, seed, ground: { name: gName, p: Grounds[gName].build(C.makeRng(`${seed}:g`), gOpts) }, figure: null, accent: null, inkSeed: `${seed}:ink`, mis: [r.range(-0.01, 0.01), r.range(0.003, 0.01)] };
    if (f) {
      const layout = r.pick(HOME[f.name] || ['centre', 'centre', 'big', 'left', 'right']);
      const p = Prims[f.name].build(C.makeRng(`${seed}:f`), { ...LAYOUT[layout] }, 'figure');
      if (f.kind) p.kind = f.kind;
      comp.figure = { name: f.name, kind: f.kind || p.kind || null, layout, p };
    }
    if (a && (!f || a.name !== f.name)) {
      const fig = comp.figure ? LAYOUT[comp.figure.layout] : LAYOUT.centre, ang = r.range(0, Math.PI * 2), d = fig.s * r.range(1.1, 1.45);
      const pl = { cx: C.clamp(fig.cx + Math.cos(ang) * d, 0.15, 0.85), cy: C.clamp(fig.cy + Math.sin(ang) * d * 0.7 - 0.06, 0.14, 0.62), s: r.range(0.06, 0.09) };
      const p = Prims[a.name].build(C.makeRng(`${seed}:a`), pl, 'accent');
      if (a.kind) p.kind = a.kind;
      comp.accent = { name: a.name, kind: a.kind || null, p };
    }
    return comp;
  }
  // Noise colours take their colour from the id; nothing else needs extras.
  const extrasFor = (id) => (id.startsWith('noise-') ? { ground: { colour: id.slice(6) } } : {});
  const buildFor = (id, kind, seed) => build(classOf(id, kind), seed ?? id, extrasFor(id));

  // A preset: the loudest layer's ground and figure; the next layer's
  // figure becomes the accent, so the blend reads as one place.
  function buildPreset(preset, seed) {
    const L = preset.layers.slice().sort((a, b) => b[1] - a[1]);
    const base = buildFor(L[0][0], 'sound', `${seed ?? preset.id}`);
    if (L[1]) {
      const sub = buildFor(L[1][0], 'sound', `${seed ?? preset.id}:${L[1][0]}`);
      const pick = sub.figure || (sub.ground.name === 'grain' ? null : null);
      if (pick && (!base.figure || pick.name !== base.figure.name)) {
        const fig = base.figure ? LAYOUT[base.figure.layout] : LAYOUT.centre, pl = { cx: fig.cx > 0.5 ? 0.24 : 0.76, cy: 0.28, s: 0.12 };
        const p = Prims[pick.name].build(C.makeRng(`${seed ?? preset.id}:blend`), pl, 'accent');
        if (pick.kind) p.kind = pick.kind;
        base.accent = { name: pick.name, kind: pick.kind, p };
      }
    }
    base.cls = 'preset'; base.preset = preset.id;
    return base;
  }

  // ---------- candidates for curation ----------
  // Eight seeds per item, chosen from a wider pool to cover as many
  // different (ground, figure) pairs as the map allows.
  function candidates(item, n = 8) {
    const make = (s) => (item.kind === 'preset' ? buildPreset(item, s) : buildFor(item.id, item.kind, s));
    const pool = Array.from({ length: 40 }, (_, i) => make(`${item.id}#${i}`)), out = [], seen = new Set();
    for (const c of pool) { const key = `${c.ground.name}|${c.figure && c.figure.name}|${c.figure && c.figure.kind}`; if (!seen.has(key)) { seen.add(key); out.push(c); } if (out.length >= n) break; }
    for (const c of pool) { if (out.length >= n) break; if (!out.includes(c)) out.push(c); }
    return out;
  }

  // ---------- draw ----------
  const grains = new Map();
  let paperPx = null;
  function grainFor(c, px, H) {
    const ph = Math.round(px * H), key = `${C.hex(c.tile)}|${px}|${ph}`;
    if (grains.has(key)) return grains.get(key);
    const cv = document.createElement('canvas'); cv.width = px; cv.height = ph;
    const g = cv.getContext('2d'), img = g.createImageData(px, ph), d = img.data, r = C.makeRng('grain4'), tile = C.rgb(c.tile), deep = C.rgb(c.deep), light = C.lum(c.tile) > 0.35;
    paperPx = paperPx || C.paperTex().getContext('2d').getImageData(0, 0, 256, 256).data;
    for (let y = 0; y < ph; y++) for (let x = 0; x < px; x++) {
      const i = (y * px + x) * 4, vig = Math.max(0, Math.hypot(x / px - 0.5, (y / ph - 0.5) * H) - 0.38) / 0.4;
      if (r.next() < 0.004) { d[i] = tile[0]; d[i + 1] = tile[1]; d[i + 2] = tile[2]; d[i + 3] = 110; continue; }
      const v = (paperPx[((y & 255) * 256 + (x & 255)) * 4] - 128) / 128;
      if (v > 0) { d[i] = d[i + 1] = d[i + 2] = 255; d[i + 3] = v * (light ? 38 : 22); } else { d[i] = deep[0]; d[i + 1] = deep[1]; d[i + 2] = deep[2]; d[i + 3] = -v * (light ? 32 : 40) + vig * 26; }
    }
    g.putImageData(img, 0, 0);
    if (grains.size > 30) grains.delete(grains.keys().next().value);
    grains.set(key, cv);
    return cv;
  }
  // o: still, px, H (height/width), scrim, only ('ground' | 'figure')
  function draw(ctx, comp, pal, t, o = {}) {
    const H = o.H || 1, c = C.roles(pal), G = Grounds[comp.ground.name], k = inks(c, G.tone(c, comp.ground.p), C.makeRng(comp.inkSeed)), still = !!o.still;
    if (o.only === 'figure') { ctx.fillStyle = css(Grounds.paper.tone(c, { key: 'light', k: 0.04 })); ctx.fillRect(0, 0, 1, H); }
    else G.draw(ctx, comp.ground.p, c, t, still, H);
    if (o.only !== 'ground') {
      ctx.save();
      if (H < 1) { ctx.translate((1 - H) / 2, 0); ctx.scale(H, H); }
      const kf = o.only === 'figure' ? inks(c, Grounds.paper.tone(c, { key: 'light', k: 0.04 }), C.makeRng(comp.inkSeed)) : k;
      // Fire is always warm, whatever the palette's form colour is.
      const kfig = comp.figure && comp.figure.name === 'fire' ? { ...kf, main: mix(c.accent, c.form, 0.25), alt: c.accent, line: mix(c.deep, c.form, 0.35), glow: mix(c.accent, c.light, 0.5) } : kf;
      if (comp.figure) Prims[comp.figure.name].draw(ctx, comp.figure.p, kfig, t, still);
      if (comp.accent) { ctx.save(); ctx.translate(comp.mis[0], comp.mis[1]); ctx.globalCompositeOperation = C.lum(kf.paper) > 0.3 ? 'multiply' : 'screen'; Prims[comp.accent.name].draw(ctx, comp.accent.p, { ...kf, main: kf.alt, alt: kf.main }, t, still); ctx.restore(); }
      ctx.restore();
    }
    if (o.scrim) { const g = ctx.createLinearGradient(0, H * 0.5, 0, H); g.addColorStop(0, css(c.deep, 0)); g.addColorStop(1, css(c.deep, 0.6)); ctx.fillStyle = g; ctx.fillRect(0, H * 0.5, 1, H * 0.5); }
    ctx.drawImage(grainFor(c, o.px || 256, H), 0, 0, 1, H);
  }

  // ---------- frozen form ----------
  // Plain data: names, variants, layout, seeds and every numeric parameter
  // (rounded), with derived caches and functions left out.
  const plain = (v) => JSON.parse(JSON.stringify(v, (key, val) => (key.startsWith('_') ? undefined : typeof val === 'number' ? Math.round(val * 1e4) / 1e4 : val)));
  function freeze(comp) {
    return {
      seed: comp.seed, cls: comp.cls,
      ground: { name: comp.ground.name, params: plain(comp.ground.p) },
      figure: comp.figure && { name: comp.figure.name, kind: comp.figure.kind, layout: comp.figure.layout, params: plain(comp.figure.p) },
      accent: comp.accent && { name: comp.accent.name, kind: comp.accent.kind, params: plain(comp.accent.p) },
      misregister: plain(comp.mis), inkSeed: comp.inkSeed,
    };
  }

  return { MAP, classOf, build, buildFor, buildPreset, candidates, draw, freeze, LAYOUT };
})();
