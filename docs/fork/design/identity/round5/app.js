/* The round 5 page: views, bells, the bell maker, the picker mock and
 * curation. Round 4's page script, extended. */
(() => {
  'use strict';
  const $ = (s, el = document) => el.querySelector(s), $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const PAL = Marks.PAL, reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const FIRST = /*@PICKS@*/{};
  const RECURATED = /*@RECURATED@*/[];
  const T0 = +new URLSearchParams(location.search).get('t') || 0;
  const BELLS = Prims.bell.SHIPPED;
  const state = { pal: 'tide', paused: false, sound: true, cat: 'All', picks: JSON.parse(JSON.stringify(FIRST)) };

  // ---------- views: one loop, visible canvases only, 30 fps ----------
  // A bell view is still until struck; strike() plays it once from t = 0.
  const views = new Set();
  const io = new IntersectionObserver((es) => es.forEach((e) => { const v = e.target._v; if (v) { v.visible = e.isIntersecting; v.dirty = true; } }), { rootMargin: '80px' });
  function view(cv, draw, o = {}) { const v = { cv, ctx: cv.getContext('2d'), draw, t: T0 + 3, dirty: true, visible: false, live: o.live !== false, last: 0, until: 0, striking: false }; cv._v = v; views.add(v); io.observe(cv); return v; }
  function drop(root) { $$('canvas', root).forEach((c) => { if (c._v) { io.unobserve(c); views.delete(c._v); } }); }
  function render(v) {
    const dpr = Math.min(devicePixelRatio || 1, 3), w = Math.round(v.cv.clientWidth * dpr), h = Math.round(v.cv.clientHeight * dpr);
    if (!w || !h) return;
    if (v.cv.width !== w || v.cv.height !== h) { v.cv.width = w; v.cv.height = h; }
    v.ctx.setTransform(1, 0, 0, 1, 0, 0); v.ctx.clearRect(0, 0, w, h); v.ctx.setTransform(w, 0, 0, w, 0, 0);
    v.draw(v.ctx, v.t, w, h / w);
  }
  let last = performance.now();
  (function tick(now) {
    const dt = Math.min(0.1, (now - last) / 1000); last = now;
    for (const v of views) {
      if (v.until && v.t > v.until) { v.striking = false; v.live = false; v.until = 0; v.dirty = true; }
      if (!v.visible) continue;
      const run = v.live && !reduced.matches && (!state.paused || v.striking);
      if (run) v.t += dt;
      if (v.dirty || (run && now - v.last > 32)) { render(v); v.dirty = false; v.last = now; }
    }
    requestAnimationFrame(tick);
  })(last);
  const redraw = () => views.forEach((v) => (v.dirty = true));
  const pal = () => PAL[state.pal];
  const card = (comp, o = {}) => (ctx, t, px, H) => Compose.draw(ctx, typeof comp === 'function' ? comp() : comp, pal(), t, { px, H, still: reduced.matches || o.still, ...o });

  // A bell's comp (or a function returning it); drawn at rest unless struck.
  const bellDur = (kn) => 0.8 + 3 * (0.45 + 1.25 * kn.ring);
  function bellView(cv, comp, o = {}) {
    const get = () => (typeof comp === 'function' ? comp() : comp);
    const v = view(cv, (ctx, t, px, H) => Compose.draw(ctx, get(), pal(), v.striking ? t : 0, { px, H, still: reduced.matches || !v.striking, ...o }), { live: false });
    v.strike = (sound = true) => { const c = get(), kn = c.figure.p.knobs; v.t = 0; v.striking = true; v.live = true; v.until = Math.min(16, bellDur(kn)); v.dirty = true; if (sound && state.sound) BellSynth.play(c.figure.p.preset, kn); };
    return v;
  }

  // ---------- toolbar ----------
  $('#chips').innerHTML = Marks.palettes.map((p) => `<button class="chip" data-pal="${p.id}"><span>${['tile', 'form', 'stroke', 'accent'].map((k) => `<i style="background:${p[k]}"></i>`).join('')}</span>${p.name}</button>`).join('');
  $('#chips').addEventListener('click', (e) => { const b = e.target.closest('.chip'); if (b) { state.pal = b.dataset.pal; theme(); } });
  $('#motion').addEventListener('click', () => { state.paused = !state.paused; $('#motion').textContent = state.paused ? 'Play' : 'Pause'; });
  $('#sound').addEventListener('click', () => { state.sound = !state.sound; $('#sound').textContent = state.sound ? 'Sound on' : 'Sound off'; $('#sound').setAttribute('aria-pressed', state.sound); });
  function theme() {
    const p = pal(), r = document.documentElement.style;
    for (const k of ['bg', 'surface', 'raised', 'text', 'muted']) r.setProperty('--' + k, p.ui.light[k]);
    r.setProperty('--form', p.form);
    $$('#chips .chip').forEach((c) => c.setAttribute('aria-pressed', c.dataset.pal === state.pal));
    redraw();
  }

  // ---------- 01 grounds, 02 figures ----------
  const bare = (seed) => { const c = Compose.build('single', seed); c.figure = null; c.accent = null; return c; };
  const NEWG = [['window', {}], ['balcony', { variant: 'balcony' }], ['balcony', { variant: 'terrace' }], ['car', {}], ['metro', {}], ['room', {}]];
  $('#grounds').innerHTML = NEWG.map(([k, o]) => `<figure class="cell"><canvas></canvas><figcaption><b>${o.variant || Grounds[k].label}</b><br><small>${Grounds[k].motion}</small></figcaption></figure>`).join('');
  $$('#grounds canvas').forEach((cv, i) => { const [k, o] = NEWG[i], c = bare('g:' + k + i); c.ground = { name: k, p: Grounds[k].build(Core.makeRng('ground5:' + k + i), o) }; view(cv, card(c)); });
  const NEWF = ['lamp', 'window', 'cup', 'porthole', 'fan', 'umbrella', 'railing', 'droplets', 'strap', 'doorway'];
  const FLAY = { cup: 'low', railing: 'low', strap: 'high' };
  $('#figures').innerHTML = NEWF.map((k) => `<figure class="cell"><canvas></canvas><figcaption><b>${Prims[k].label}</b><br><small>${Prims[k].motion}</small></figcaption></figure>`).join('');
  $$('#figures canvas').forEach((cv, i) => { const k = NEWF[i], c = bare('f:' + k), lay = FLAY[k] || 'centre'; c.figure = { name: k, layout: lay, p: Prims[k].build(Core.makeRng('figure5:' + k), { ...Compose.LAYOUT[lay] }, 'figure') }; view(cv, card(c, { only: 'figure' })); });

  // ---------- candidates and picks ----------
  const cands = new Map();
  const candsOf = (item) => { const key = item.id + '|' + item.kind; if (!cands.has(key)) cands.set(key, Compose.candidates(item, item.kind === 'bellicon' ? 3 : 8)); return cands.get(key); };
  const picked = (item) => candsOf(item)[state.picks[item.id] ?? 0];
  const bellCard = (b) => () => candsOf({ id: b.id, kind: 'bell' })[(state.picks[b.id] || {}).card ?? 0];
  const bellIcon = (b) => () => candsOf({ id: b.id, kind: 'bellicon' })[(state.picks[b.id] || {}).icon ?? 0];
  const byId = (id) => Shipped.all.find((x) => x.id === id);

  // ---------- 03 noise ----------
  const NOISE = ['noise-white', 'noise-pink', 'noise-brown'].map(byId);
  $('#noise').innerHTML = NOISE.map((it) => `<figure class="cell"><canvas></canvas><figcaption>${it.title}</figcaption></figure>`).join('') + `<figure class="cell"><canvas></canvas><figcaption>Stillness <small>preset</small></figcaption></figure>`;
  $$('#noise canvas').forEach((cv, i) => view(cv, (ctx, t, px, H) => Compose.draw(ctx, picked(i < 3 ? NOISE[i] : byId('starter-stillness')), pal(), t, { px, H, scrim: true, still: true }), { live: false }));

  // ---------- 04 bells ----------
  const knobLine = (kn) => `${Math.round(kn.pitch)} Hz · bright ${Math.round(kn.bright * 100)}% · ring ${kn.ring < 0.1 ? kn.ring.toFixed(3) : kn.ring.toFixed(2)} s<br>strike ${kn.strike.toFixed(2)} · shimmer ${kn.shimmer.toFixed(2)} Hz`;
  $('#bells').innerHTML = BELLS.map((b) => `<figure class="cell"><button aria-label="Strike the ${b.title}"><canvas></canvas><span><b>${b.title}</b><br><span class="kv">${knobLine(BellData[b.preset].knobs)}</span></span></button></figure>`).join('');
  $$('#bells button').forEach((btn, i) => { const v = bellView($('canvas', btn), bellCard(BELLS[i])); btn.addEventListener('click', () => v.strike()); });

  // ---------- 05 the bell maker ----------
  const K = Prims.bell.KNOBS;
  const KNOB_UI = [
    ['pitch', 'Size and pitch', 'how big it is drawn, and its proportions'],
    ['bright', 'Brightness', 'the upper partials: rim, ink and highlight'],
    ['ring', 'Ring', 'how long it keeps moving and rippling'],
    ['strike', 'Strike', 'soft mallet to hard: how hard it is knocked'],
    ['shimmer', 'Shimmer', 'the beat: how fast and deep the rim flickers'],
  ];
  const toSlider = (n, v) => { const [lo, hi, , sc] = K[n]; return Math.round(1000 * (sc === 'log' ? Math.log(v / lo) / Math.log(hi / lo) : (v - lo) / (hi - lo))); };
  const fromSlider = (n, x) => { const [lo, hi, , sc] = K[n], u = x / 1000; return sc === 'log' ? lo * Math.pow(hi / lo, u) : lo + (hi - lo) * u; };
  const fmt = (n, v) => (n === 'pitch' ? `${Math.round(v)} Hz` : n === 'ring' ? `${v < 0.1 ? v.toFixed(3) : v.toFixed(2)} s` : n === 'shimmer' ? `${v.toFixed(2)} Hz` : n === 'bright' ? `${Math.round(v * 100)}%` : v < 0.34 ? `soft · ${v.toFixed(2)}` : v < 0.67 ? `medium · ${v.toFixed(2)}` : `hard · ${v.toFixed(2)}`);
  const mk = { preset: 'bowl_medium', knobs: null, card: null, icon: null };
  function mkLoad(preset) {
    mk.preset = preset; mk.knobs = { ...BellData[preset].knobs };
    const b = BELLS.find((x) => x.preset === preset);
    mk.card = Compose.build('bell', 'maker:' + preset, { figure: { preset } }); mk.card.figure.layout = 'big'; Object.assign(mk.card.figure.p, Compose.LAYOUT.big); mk.card.figure.p.knobs = mk.knobs;
    const ic = bellIcon(b)(); mk.icon = { ...ic, figure: { ...ic.figure, p: { ...ic.figure.p, knobs: mk.knobs } } };
    $$('#pres .pre').forEach((x) => x.setAttribute('aria-pressed', x.dataset.p === preset));
    KNOB_UI.forEach(([n]) => { $(`#k-${n}`).value = toSlider(n, mk.knobs[n]); });
    mkShow();
  }
  function mkShow() {
    KNOB_UI.forEach(([n]) => { $(`#kv-${n}`).textContent = fmt(n, mk.knobs[n]); });
    const r = (x) => +x.toPrecision(3);
    $('#mk-json').textContent = JSON.stringify({ from: mk.preset, pitch: r(mk.knobs.pitch), bright: r(mk.knobs.bright), ring: r(mk.knobs.ring), strike: r(mk.knobs.strike), shimmer: r(mk.knobs.shimmer) }).replace(/,/g, ", ");
    mkCard.dirty = true; mkIcon.dirty = true;
  }
  $('#pres').innerHTML = BELLS.map((b) => `<button class="pre" data-p="${b.preset}">${b.title}</button>`).join('');
  $('#knobs').innerHTML = KNOB_UI.map(([n, label, hint]) => `<div class="knob"><label for="k-${n}"><b>${label}</b><span id="kv-${n}"></span></label><input type="range" id="k-${n}" min="0" max="1000" step="1"><small>${hint}</small></div>`).join('');
  const mkCard = bellView($('#mk-card'), () => mk.card), mkIcon = bellView($('#mk-icon'), () => mk.icon);
  const mkStrike = () => { mkCard.strike(); mkIcon.strike(false); };
  $('#pres').addEventListener('click', (e) => { const b = e.target.closest('.pre'); if (b) { mkLoad(b.dataset.p); mkStrike(); } });
  KNOB_UI.forEach(([n]) => { const el = $(`#k-${n}`); el.addEventListener('input', () => { mk.knobs[n] = Prims.bell.clampKnob(n, fromSlider(n, +el.value)); mkShow(); }); el.addEventListener('change', mkStrike); });
  $('#mk-strike').addEventListener('click', mkStrike);

  // ---------- 06 the picker mock ----------
  const FAM = { swell: 'Medito’s bell', bowl: 'Singing bowl', temple: 'Bonshō', hand: 'Hand bell', chime: 'Struck bar', tingsha: 'Cymbals', block: 'Wood', fish: 'Wood', gong: 'Tam-tam' };
  let chosen = 'bell-swell';
  $('#picker').innerHTML = `<div class="row" role="radio" tabindex="0" data-id="off"><span class="off"></span><span class="t">Off</span><span class="radio"></span></div>` +
    BELLS.map((b) => { const kn = BellData[b.preset].knobs; return `<div class="row" role="radio" tabindex="0" data-id="${b.id}"><canvas class="ic"></canvas><span class="t">${b.title}<small>${FAM[b.kind]} · rings ${kn.ring < 0.2 ? 'briefly' : `about ${Math.round(kn.ring * 3)} s`}</small></span><span class="radio"></span></div>`; }).join('') +
    `<div class="row own" role="radio" tabindex="0" aria-disabled="true"><span class="off" style="border-style:solid"></span><span class="t">Design your own…<small>BJS-587 · see “Make a bell”</small></span></div>`;
  const pickerViews = {};
  $$('#picker .row[data-id]').forEach((row) => {
    const b = BELLS.find((x) => x.id === row.dataset.id);
    if (b) pickerViews[b.id] = bellView($('canvas', row), bellIcon(b));
    const choose = () => { chosen = row.dataset.id; $$('#picker .row[data-id]').forEach((r) => r.setAttribute('aria-checked', r.dataset.id === chosen)); if (b) pickerViews[b.id].strike(); };
    row.addEventListener('click', choose);
    row.addEventListener('keydown', (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); choose(); } });
  });
  $$('#picker .row[data-id]').forEach((r) => r.setAttribute('aria-checked', r.dataset.id === chosen));

  // ---------- 07 meaning map ----------
  const LEGACY = ['rain', 'room', 'fan', 'train'];
  const idsOf = (cls) => [...Shipped.all.filter((x) => x.kind !== 'preset' && Compose.classOf(x.id, x.kind) === cls).map((x) => x.title), ...(cls === 'bell' || cls === 'bellicon' ? BELLS.map((b) => b.title) : [])];
  const list = (a) => a.map((x) => (x ? `<code>${x}</code>` : '<code>none</code>')).join(' ');
  const pairs = (ps) => ps.map(([g, f]) => `<code>${g}</code> + <code>${f || 'nothing'}</code>`).join('<br>');
  $('#map').innerHTML = `<tr><th>Class</th><th>Grounds</th><th>Figures</th><th>Accents</th><th>Ships as</th></tr>` + Object.entries(Compose.MAP).map(([k, m]) => `<tr><td><b>${m.label}</b>${m.pairs ? ' <span class="new">5</span>' : ''}</td>${m.pairs ? `<td colspan="2">${pairs(m.pairs)}</td>` : `<td>${list(m.grounds)}</td><td>${list(m.figures)}</td>`}<td>${list(m.accents.filter((x, i, a) => a.indexOf(x) === i))}</td><td>${LEGACY.includes(k) ? '<span class="status">presets’ layers (round 4)</span>' : k === 'bellicon' ? 'every bell’s icon' : (idsOf(k).join(', ') || '<span class="status">by rule</span>')}</td></tr>`).join('') + `<tr><td><b>Presets</b></td><td colspan="4">the loudest layer's ground and figure, with the next layer's figure as the accent, through round 4's classes</td></tr>`;

  // ---------- 08 curation ----------
  const CATS = ['All', 'Re-curated', ...new Set(Shipped.all.map((x) => x.cat)), 'Bells'];
  $('#cats').innerHTML = CATS.map((c) => `<button class="chip" data-cat="${c}">${c}</button>`).join('');
  $('#cats').addEventListener('click', (e) => { const b = e.target.closest('.chip'); if (b) { state.cat = b.dataset.cat; renderItems(); } });
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  function status() {
    const ids = [...Shipped.all.map((x) => x.id), ...BELLS.map((b) => b.id)], changed = ids.filter((id) => !same(state.picks[id] ?? 0, FIRST[id] ?? 0)).length;
    $('#status').innerHTML = `<b>${ids.filter((id) => id in state.picks).length}</b> of ${ids.length} shipped items curated · <b>${changed}</b> changed from the committed picks`;
  }
  const candRow = (n, cls = '') => Array.from({ length: n }, (_, i) => `<button class="cand ${cls}" data-i="${i}" aria-label="Candidate ${i + 1}"><canvas></canvas></button>`).join('');
  function renderItems() {
    const host = $('#items'); drop(host);
    $$('#cats .chip').forEach((c) => c.setAttribute('aria-pressed', c.dataset.cat === state.cat));
    const items = Shipped.all.filter((x) => state.cat === 'All' || x.cat === state.cat || (state.cat === 'Re-curated' && RECURATED.includes(x.id)));
    const bells = state.cat === 'All' || state.cat === 'Bells' || state.cat === 'Re-curated' ? BELLS : [];
    host.innerHTML = items.map((it) => `<div class="item" data-id="${it.id}"><header><span><b>${it.title}</b>${RECURATED.includes(it.id) ? '<span class="new">new</span>' : ''} <small>${it.cat} · ${it.kind === 'preset' ? 'preset' : Compose.MAP[Compose.classOf(it.id, it.kind)].label}</small></span><small class="pickno"></small></header><div class="cands">${candRow(8)}</div></div>`).join('') +
      bells.map((b) => `<div class="item bell" data-bell="${b.id}"><header><span><b>${b.title}</b><span class="new">new</span> <small>Bell · <code>${b.asset.split('/').pop()}</code></small></span><small class="pickno"></small></header><div class="lab">Card</div><div class="cands">${candRow(8)}</div><div class="lab">Icon, 40 dp</div><div class="icands">${candRow(3, 'icon')}</div></div>`).join('');
    $$('.item[data-id]', host).forEach((el) => {
      const it = byId(el.dataset.id), cs = candsOf(it);
      $$('.cand', el).forEach((b, i) => {
        const v = view($('canvas', b), card(cs[i], { scrim: it.kind === 'sound' || it.kind === 'preset' }), { live: false });
        b._v = v;
        if (i === FIRST[it.id]) b.insertAdjacentHTML('beforeend', '<span class="was">committed</span>');
        b.addEventListener('click', () => { state.picks[it.id] = i; markItem(el, it); status(); });
      });
      markItem(el, it);
    });
    $$('.item[data-bell]', host).forEach((el) => {
      const b = BELLS.find((x) => x.id === el.dataset.bell), cc = candsOf({ id: b.id, kind: 'bell' }), ic = candsOf({ id: b.id, kind: 'bellicon' });
      $$('.cands .cand', el).forEach((btn, i) => { btn._v = bellView($('canvas', btn), cc[i]); if (i === FIRST[b.id].card) btn.insertAdjacentHTML('beforeend', '<span class="was">committed</span>'); btn.addEventListener('click', () => { state.picks[b.id] = { ...state.picks[b.id], card: i }; markBell(el, b); status(); btn._v.strike(); }); });
      $$('.icands .cand', el).forEach((btn, i) => { btn._v = bellView($('canvas', btn), ic[i]); btn.addEventListener('click', () => { state.picks[b.id] = { ...state.picks[b.id], icon: i }; markBell(el, b); status(); btn._v.strike(false); }); });
      markBell(el, b);
    });
    status();
  }
  // The current pick animates; the other candidates stay still.
  function markItem(el, it) {
    const p = state.picks[it.id] ?? 0, c = candsOf(it)[p];
    $$('.cand', el).forEach((b, i) => { b.setAttribute('aria-pressed', i === p); b._v.live = i === p; b._v.dirty = true; });
    $('.pickno', el).textContent = `${c.ground.name}${c.ground.p.variant ? ':' + c.ground.p.variant : ''}${c.figure ? ' · ' + c.figure.name + (c.figure.kind ? ':' + c.figure.kind : '') : ''}${c.accent ? ' + ' + c.accent.name : ''}`;
  }
  function markBell(el, b) {
    const p = state.picks[b.id] || { card: 0, icon: 0 };
    $$('.cands .cand', el).forEach((x, i) => { x.setAttribute('aria-pressed', i === p.card); x._v.dirty = true; });
    $$('.icands .cand', el).forEach((x, i) => { x.setAttribute('aria-pressed', i === p.icon); x._v.dirty = true; });
    $('.pickno', el).textContent = `card on ${candsOf({ id: b.id, kind: 'bell' })[p.card].ground.name} · icon on ${candsOf({ id: b.id, kind: 'bellicon' })[p.icon].ground.name}`;
    Object.values(pickerViews).forEach((v) => (v.dirty = true)); redraw();
  }
  $('#reset').addEventListener('click', () => { state.picks = JSON.parse(JSON.stringify(FIRST)); renderItems(); redraw(); });
  $('#export').addEventListener('click', async () => {
    const json = JSON.stringify(Export.curated(state.picks), null, 1) + '\n';
    $('#json').value = json; $('#jsonbox').hidden = false;
    try { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' })); a.download = 'curated_art.json'; a.click(); } catch {}
    try { await navigator.clipboard.writeText(json); $('#export').textContent = 'Exported and copied'; } catch { $('#export').textContent = 'Exported'; }
    setTimeout(() => ($('#export').textContent = 'Export curated_art.json'), 2000);
  });

  renderItems();
  mkLoad('bowl_medium');
  theme();
  reduced.addEventListener?.('change', redraw);
})();
