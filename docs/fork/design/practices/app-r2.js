/* Round 2 page: for each practice, round 1's tile beside its new variants,
 * on phone-sized tiles (170 dp, as layout A), in Tidewater light and dark.
 * ?shot=<practice id>|fixes|sheet renders one block alone, for PNG stills;
 * ?t=<seconds> freezes the clock there; ?still draws the calm frames. */
(() => {
  'use strict';
  const C = Core, { mix, css } = C;
  const DATA = /*@DATA@*/{};
  const TIDE = { tile: '#E5EAEC', form: '#86A9B1', stroke: '#1E2C3A', accent: '#DE8A62' };
  const ROLES = { light: C.roles(TIDE), dark: C.roles(TIDE, { tile: '#1A2631', stroke: '#E6EDF0' }) };
  const params = new URLSearchParams(location.search);
  const FROZEN = params.has('t') ? Number(params.get('t')) : null;
  const STILL = params.has('still');
  const EMPTY = { label: '(not drawn yet)', says: '', build: (r, pl) => pl, draw() {} };
  const R3 = typeof PracticesR3 === 'undefined' ? {} : PracticesR3;
  const fig = (key) => R3[key] || PracticesR2[key] || Practices[key] || EMPTY;

  // Inks as round 1's page (round 5's compose), seeded per practice.
  function inks(c, tone, r) {
    const light = C.lum(tone) > 0.3;
    const strong = light ? [c.stroke, mix(c.stroke, c.form, 0.35), c.deep].filter((x) => C.contrast(x, tone) > 2) : [c.light, mix(c.light, c.accent, 0.3)];
    const main = r.pick(strong.filter((x) => C.contrast(x, tone) > 1.4)) || strong[0];
    const alt = C.contrast(c.accent, tone) > 1.3 ? c.accent : mix(c.accent, light ? c.stroke : c.light, 0.35);
    return { paper: tone, main, alt, line: light ? mix(c.stroke, tone, 0.25) : mix(c.light, tone, 0.25), glow: mix(c.accent, c.light, 0.45) };
  }

  // A composition is a practice id, a figure and a ground; round 1's tiles
  // keep round 1's seeds, so they look exactly as they did.
  const comps = new Map();
  function comp(id, v, theme) {
    const key = `${id}|${v.figure}|${v.ground}|${theme}`;
    if (comps.has(key)) return comps.get(key);
    const seed = v.r1 ? `practice:${v.r1}` : `practice:${id}:${v.figure}`;
    const c = ROLES[theme], g = Grounds[v.ground].build(C.makeRng(`${seed}:g`), { key: 'light', ...(v.gopts || {}) });
    const f = fig(v.figure), fp = f.build(C.makeRng(`${seed}:f`), { cx: 0.5, cy: 0.5, s: 0.3 });
    const k = inks(c, Grounds[v.ground].tone(c, g), C.makeRng(`${seed}:ink`));
    const out = { c, g, f, fp, k };
    comps.set(key, out);
    return out;
  }
  function paint(cv, t, still) {
    const v = JSON.parse(cv.dataset.v), W = cv.width, H = cv.height / W, { c, g, f, fp, k } = comp(cv.dataset.id, v, cv.dataset.theme), ctx = cv.getContext('2d');
    ctx.setTransform(W, 0, 0, W, 0, 0);
    Grounds[v.ground].draw(ctx, g, c, t, still, H);
    ctx.save();
    const side = Math.min(1, H);
    ctx.translate((1 - side) / 2, H * 0.52 - side / 2);
    ctx.scale(side, side);
    f.draw(ctx, fp, k, t, still);
    ctx.restore();
  }

  // ---------- markup ----------
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s).replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[m]);
  const art = (id, v, theme) => { const cv = el('canvas', 'art'); cv.dataset.id = id; cv.dataset.theme = theme; cv.dataset.v = JSON.stringify(v); cv.style.width = '170px'; cv.style.height = '148px'; return cv; };
  const LETTERS = 'ABCDE';

  function tile(p, v, theme, tag, pick) {
    const f = fig(v.figure), t = el('div', `tile${pick ? ' pick' : ''}${tag === 'R1' ? ' was' : ''}`);
    t.append(art(p.id, v, theme));
    t.append(el('div', 'txt', `<div class="tag">${tag === 'R1' ? 'Round 1' : tag.length > 1 ? tag : `Variant ${tag}`}${pick ? '<span class="badge">pick</span>' : ''}</div><div class="name">${esc(f.label)}</div><div class="says">${esc(f.says)}</div><div class="gr">${esc(v.ground)}${v.library ? `<span class="lib" title="figure library: ${({ any: 'may be drawn for any user content', practice: 'only for content about this practice', none: 'kept out of the library' })[v.library]}">library: ${esc(v.library)}</span>` : ''}</div>`));
    return t;
  }
  function block(p, compact = false) {
    const b = el('section', 'block');
    b.id = p.id;
    b.append(el('div', 'bhead', `<span class="pname">${esc(p.name)}</span>${p.script ? ` <span class="script">${esc(p.script)}</span>` : ''} <span class="lang">${esc(p.lang)}</span>`));
    if (!compact) {
      b.append(el('p', 'desc', esc(p.desc)));
      if (p.why) b.append(el('p', 'why', p.why));
    }
    ['light', 'dark'].forEach((theme) => {
      const row = el('div', `row ${theme}`);
      row.append(tile(p, { ...p.was, r1: p.was.r1 || p.id }, theme, 'R1'));
      (p.also || []).forEach((v) => row.append(tile(p, v, theme, v.tag)));
      p.variants.forEach((v, i) => row.append(tile(p, v, theme, LETTERS[i], p.pick === i)));
      b.append(row);
    });
    return b;
  }
  function fixesBlock() {
    const b = el('section', 'block');
    b.id = 'fixes';
    b.append(el('div', 'bhead', '<span class="pname">Small fixes</span>'));
    ['light', 'dark'].forEach((theme) => {
      const row = el('div', `row ${theme}`);
      DATA.fixes.forEach((x) => { const t = tile({ id: x.id }, { figure: x.figure, ground: x.ground, r1: x.id }, theme, 'R1'); t.querySelector('.tag').textContent = x.label; t.querySelector('.says').textContent = x.what; row.append(t); });
      b.append(row);
    });
    return b;
  }

  function build() {
    const P = DATA.practices.map((p) => ({ ...p, was: { ...p.was, r1: p.was.r1 || (p.id === 'mahamudra' ? 'dzogchen' : p.id === 'trataka' || p.id === 'kasina' ? 'gazing' : p.id) } }));
    const shot = params.get('shot');
    if (shot) {
      document.body.className = 'shotmode';
      const host = el('div', 'shot');
      if (shot === 'fixes') host.append(fixesBlock());
      else if (shot === 'sheet') { host.classList.add('sheet'); if (P.length <= 8) { host.style.width = '2380px'; host.style.columns = '2'; } P.forEach((p) => host.append(block(p, true))); }
      else host.append(block(P.find((p) => p.id === shot)));
      document.body.append(host);
      return;
    }
    const host = document.getElementById('blocks');
    P.forEach((p) => host.append(block(p)));
    if ((DATA.fixes || []).length) host.append(fixesBlock());
    const flags = document.getElementById('flags');
    if (!(DATA.flags || []).length) document.getElementById('flagbox').remove();
    (DATA.flags || []).forEach((x) => flags.append(el('li', '', `<b>${esc(x.name)}</b> (${esc(x.figure)}): ${esc(x.what)}`)));
  }

  // ---------- the clock: draw only what is on screen ----------
  build();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const visible = new Set();
  const all = [...document.querySelectorAll('canvas.art')];
  all.forEach((cv) => { cv.width = Math.round(170 * dpr); cv.height = Math.round(148 * dpr); });
  if ('IntersectionObserver' in window && FROZEN == null) {
    const io = new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? visible.add(e.target) : visible.delete(e.target))), { rootMargin: '120px' });
    all.forEach((cv) => io.observe(cv));
  } else all.forEach((cv) => visible.add(cv));
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const t0 = performance.now();
  function frame(now) {
    const t = FROZEN ?? (now - t0) / 1000 + 3;
    visible.forEach((cv) => paint(cv, reduce ? 0 : t, STILL || reduce));
    if (FROZEN == null && !STILL && !reduce) requestAnimationFrame(frame);
  }
  all.forEach((cv) => paint(cv, FROZEN ?? 3, STILL || reduce));
  window.__paint = paint; // for check_r2.mjs
  window.__ready = true;
  requestAnimationFrame(frame);
})();
