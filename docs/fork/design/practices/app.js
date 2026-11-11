/* The exploration page: a composition per practice (a curated ground and the
 * practice's figure, in Tidewater), the gallery of all 36, the names table,
 * and three tile layouts in light and dark at phone width.
 * ?shot=<layout>-<theme> renders one phone frame alone, for PNG stills;
 * ?t=<seconds> freezes the clock there. */
(() => {
  'use strict';
  const C = Core, { mix, css } = C;
  const DATA = /*@DATA@*/{};
  const TIDE = { tile: '#E5EAEC', form: '#86A9B1', stroke: '#1E2C3A', accent: '#DE8A62' };
  const UI = {
    light: { bg: '#F2F5F6', surface: '#E4EAEC', raised: '#D7E0E3', text: '#18242F', muted: '#5E6F7B' },
    dark: { bg: '#0E151C', surface: '#162029', raised: '#1F2B36', text: '#E6EDF0', muted: '#8DA0AC' },
  };
  const ROLES = { light: C.roles(TIDE), dark: C.roles(TIDE, { tile: '#1A2631', stroke: '#E6EDF0' }) };
  const GROUPS = [['heart', 'Heart'], ['concentration', 'Concentration'], ['insight', 'Insight'], ['awareness', 'Awareness'], ['body', 'Body & energy'], ['devotion', 'Sound & devotion'], ['imagination', 'Imagination']];
  const P = DATA.practices;
  const params = new URLSearchParams(location.search);
  const FROZEN = params.has('t') ? Number(params.get('t')) : null;
  const STILL = params.has('still');

  // ---------- inks: as round 5's compose, seeded per practice ----------
  function inks(c, tone, r) {
    const light = C.lum(tone) > 0.3;
    const strong = light ? [c.stroke, mix(c.stroke, c.form, 0.35), c.deep].filter((x) => C.contrast(x, tone) > 2) : [c.light, mix(c.light, c.accent, 0.3)];
    const main = r.pick(strong.filter((x) => C.contrast(x, tone) > 1.4)) || strong[0];
    const alt = C.contrast(c.accent, tone) > 1.3 ? c.accent : mix(c.accent, light ? c.stroke : c.light, 0.35);
    return { paper: tone, main, alt, line: light ? mix(c.stroke, tone, 0.25) : mix(c.light, tone, 0.25), glow: mix(c.accent, c.light, 0.45) };
  }

  // ---------- compositions, cached per practice and theme ----------
  const comps = new Map();
  function comp(p, theme) {
    const key = `${p.id}|${theme}`;
    if (comps.has(key)) return comps.get(key);
    const c = ROLES[theme], g = Grounds[p.ground].build(C.makeRng(`practice:${p.id}:g`), { key: 'light' });
    const f = Practices[p.figure], fp = f.build(C.makeRng(`practice:${p.id}:f`), { cx: 0.5, cy: 0.5, s: 0.3 });
    const k = inks(c, Grounds[p.ground].tone(c, g), C.makeRng(`practice:${p.id}:ink`));
    // fire-warm figures keep their warmth whatever the theme
    const v = { c, g, f, fp, k };
    comps.set(key, v);
    return v;
  }
  // H = height / width. The figure sits in the square at the centre of the
  // art, scaled to the shorter side, nudged by `fy` (0.5 = centre).
  function paint(cv, p, theme, t, still, o = {}) {
    const W = cv.width, Hpx = cv.height, H = Hpx / W, { c, g, f, fp, k } = comp(p, theme), ctx = cv.getContext('2d');
    ctx.setTransform(W, 0, 0, W, 0, 0);
    Grounds[p.ground].draw(ctx, g, c, t, still, H);
    ctx.save();
    const side = Math.min(1, H) * (o.scale || 1), fy = o.fy ?? 0.5;
    ctx.translate(o.fx != null ? o.fx - side / 2 : (1 - side) / 2, H * fy - side / 2);
    ctx.scale(side, side);
    f.draw(ctx, fp, k, t, still);
    ctx.restore();
    if (o.scrim) { const gr = ctx.createLinearGradient(0, H * 0.35, 0, H); gr.addColorStop(0, css(c.deep, 0)); gr.addColorStop(1, css(theme === 'dark' ? '#0B1117' : '#18242F', 0.78)); ctx.fillStyle = gr; ctx.fillRect(0, 0, 1, H); }
  }

  // ---------- markup ----------
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s).replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[m]);
  const art = (p, theme, w, h, o = {}) => { const cv = el('canvas', 'art'); cv.dataset.id = p.id; cv.dataset.theme = theme; cv.dataset.o = JSON.stringify(o); cv.style.width = `${w}px`; cv.style.height = `${h}px`; return cv; };
  const meta = (p) => `<span class="lang">${esc(p.lang)}</span>${p.script ? `<span class="script">${esc(p.script)}</span>` : ''}`;
  const byGroup = GROUPS.map(([g, label]) => ({ g, label, items: P.filter((p) => p.group === g) }));

  function phone(theme, title, body) {
    const f = el('div', `phone ${theme}`);
    const scr = el('div', 'screen');
    scr.append(el('div', 'status', '<span>9:41</span><span>● ● ▮</span>'));
    scr.append(el('div', 'apptitle', 'Explore'));
    scr.append(el('div', 'search', '<span>⌕</span> Search practices, teachers, talks'));
    scr.append(el('div', 'section', `<span>${esc(title)}</span>`));
    scr.append(body);
    scr.append(el('div', 'navbar', '<span>Home</span><span class="on">Explore</span><span>Library</span><span>Sounds</span><span>You</span>'));
    f.append(scr);
    return f;
  }

  // A: a 2-column grid of tall tiles, grouped
  function layoutA(theme) {
    const body = el('div', 'gridA');
    byGroup.forEach(({ label, items }) => {
      body.append(el('div', 'ghead', esc(label)));
      const grid = el('div', 'grid2');
      items.forEach((p) => {
        const t = el('div', 'tileA');
        t.append(art(p, theme, 170, 148, { fy: 0.52 }));
        t.append(el('div', 'txt', `<div class="name">${esc(p.name)}</div><div class="meta">${meta(p)}</div><div class="desc">${esc(p.desc)}</div>`));
        grid.append(t);
      });
      body.append(grid);
    });
    return phone(theme, 'Ways to practise', body);
  }
  // B: one carousel of cards per group
  function layoutB(theme) {
    const body = el('div', 'carB');
    byGroup.forEach(({ label, items }) => {
      body.append(el('div', 'ghead', `${esc(label)} <span class="count">${items.length}</span>`));
      const row = el('div', 'row');
      items.forEach((p) => {
        const t = el('div', 'tileB');
        t.append(art(p, theme, 148, 132, { fy: 0.5 }));
        t.append(el('div', 'txt', `<div class="name">${esc(p.name)}</div><div class="meta">${meta(p)}</div><div class="desc">${esc(p.desc)}</div>`));
        row.append(t);
      });
      body.append(row);
    });
    return phone(theme, 'Ways to practise', body);
  }
  // C: compact tiles, the figure as the background, words over a scrim
  function layoutC(theme) {
    const body = el('div', 'gridC');
    byGroup.forEach(({ label, items }) => {
      body.append(el('div', 'ghead', esc(label)));
      const grid = el('div', 'grid2');
      items.forEach((p) => {
        const t = el('div', 'tileC');
        t.append(art(p, theme, 170, 112, { fx: 0.72, fy: 0.42, scale: 1.25, scrim: true }));
        t.append(el('div', 'over', `<div class="name">${esc(p.name)}</div><div class="meta">${meta(p)}</div>`));
        grid.append(t);
      });
      body.append(grid);
    });
    return phone(theme, 'Ways to practise', body);
  }
  const LAYOUTS = { A: [layoutA, 'A · Grid of tall tiles', 'Two columns, grouped. Figure, original name, tradition and script, a one-line description. The full browse page: room for every word, scrolls long (36 tiles, 18 rows).'], B: [layoutB, 'B · Carousels by group', 'Seven rows, one per group, each a sideways carousel of cards. Explore-shaped: a screen shows three or four groups, and the groups themselves teach the map.'], C: [layoutC, 'C · Compact, figure as background', 'Two columns of short tiles, the figure filling the tile and the words over a scrim. Densest (six rows a screen); the description waits for the practice page. Fits the Labels sheet.'] };

  function build() {
    const shot = params.get('shot');
    if (shot) {
      document.body.className = 'shotmode';
      const [L, theme] = shot.split('-');
      if (L === 'G') document.body.append(gallery(theme || 'light', true));
      else document.body.append(LAYOUTS[L][0](theme));
      return;
    }
    document.getElementById('gallery').append(gallery('light'), gallery('dark'));
    const table = document.getElementById('names');
    P.forEach((p) => {
      const tr = el('tr');
      tr.innerHTML = `<td class="tg">${esc(GROUPS.find(([g]) => g === p.group)[1])}</td><td><b>${esc(p.name)}</b>${p.script ? ` <span class="script">${esc(p.script)}</span>` : ''}</td><td>${esc(p.lang)}</td><td>${esc(p.desc)}</td><td class="en">${esc(p.english)}</td><td class="note">${esc(p.note)}</td>`;
      table.append(tr);
    });
    const lay = document.getElementById('layouts');
    Object.entries(LAYOUTS).forEach(([key, [fn, title, blurb]]) => {
      const s = el('section', 'layout');
      s.append(el('h3', '', esc(title)), el('p', 'lede', esc(blurb)));
      const pair = el('div', 'pair');
      pair.append(fn('light'), fn('dark'));
      s.append(pair);
      lay.append(s);
    });
  }
  function gallery(theme, shot = false) {
    const wrap = el('div', `gallery ${theme}${shot ? ' shot' : ''}`);
    byGroup.forEach(({ label, items }) => {
      wrap.append(el('div', 'ghead', esc(label)));
      const g = el('div', 'grid6');
      items.forEach((p) => {
        const c = el('div', 'fig');
        c.append(art(p, theme, 150, 150));
        c.append(el('div', 'cap', `<b>${esc(p.name)}</b><span>${esc(Practices[p.figure].label)}</span><i>${esc(Practices[p.figure].says)}</i>`));
        g.append(c);
      });
      wrap.append(g);
    });
    return wrap;
  }

  // ---------- the clock: draw only what is on screen ----------
  build();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const visible = new Set();
  const all = [...document.querySelectorAll('canvas.art')];
  all.forEach((cv) => { const w = parseFloat(cv.style.width), h = parseFloat(cv.style.height); cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); });
  const byId = Object.fromEntries(P.map((p) => [p.id, p]));
  const draw = (cv, t) => paint(cv, byId[cv.dataset.id], cv.dataset.theme, t, STILL, JSON.parse(cv.dataset.o));
  if ('IntersectionObserver' in window && FROZEN == null) {
    const io = new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? visible.add(e.target) : visible.delete(e.target))), { rootMargin: '120px' });
    all.forEach((cv) => io.observe(cv));
  } else all.forEach((cv) => visible.add(cv));
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const t0 = performance.now();
  function frame(now) {
    const t = FROZEN ?? (now - t0) / 1000 + 3;
    visible.forEach((cv) => draw(cv, reduce ? 0 : t));
    if (FROZEN == null && !STILL && !reduce) requestAnimationFrame(frame);
  }
  all.forEach((cv) => draw(cv, FROZEN ?? 3));
  requestAnimationFrame(frame);
})();
