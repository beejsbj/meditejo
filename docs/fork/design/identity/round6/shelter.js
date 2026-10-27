/* The minimal shelter (the house mark, m-2026-10-26) with an M in its roof.
 *
 * A port of lib/services/identity/mark_outline.dart on fork/identity
 * (blobOutline, shelterRoofCommands, settledOutline) and of
 * tools/meditejo/branding/house_mark.dart's icon mapping, so the page draws
 * exactly what the app and make_icons.py would. Round 6 adds three numbers
 * to the shelter's `values`, all in tile units and all optional (absent or 0
 * is the shelter as shipped):
 *
 *   notch  how far the apex folds down below its two shoulders: an M
 *   nw     how far each shoulder sits from the centre
 *   soft   0 for a sharp V; otherwise a dip with a round bottom, its curve
 *          reaching this far out from the centre
 *   gap    0 for one roof; otherwise a hairline between the two halves
 *
 * shelter_notch.patch makes the same change to shelterRoofCommands, so a
 * variant's JSON drops in as assets/branding/house_mark.json. */
const Shelter = (() => {
  'use strict';
  const TAU = Math.PI * 2, lerp = (a, b, t) => a + (b - a) * t;
  const THICK = 0.07; // the roof's thickness at the apex, as shipped

  // mark_outline.dart blobOutline: 129 points, the last on the first.
  function blobOutline(b, o = {}) {
    const grow = o.grow ?? 1, imperf = o.imperf ?? 1, asp = lerp(1, b.asp, imperf), m = 128, c = Math.cos(b.rot), s = Math.sin(b.rot), out = [];
    for (let i = 0; i <= m; i++) {
      const th = (i / m) * TAU;
      let r = 1;
      for (let k = 0; k < 3; k++) r += imperf * b.a[k] * Math.sin((k + 2) * th + b.p[k]);
      if (b.cut !== 0) r += b.cut * (0.6 * Math.sin(b.ck[0] * th + b.cp[0]) + 0.4 * Math.sin(b.ck[1] * th + b.cp[1]));
      r *= b.R * grow;
      const ux = r * Math.cos(th) * asp, uy = r * Math.sin(th);
      out.push([b.cx + ux * c - uy * s, b.cy + ux * s + uy * c]);
    }
    return out;
  }

  // ---------- quadratic helpers ----------
  const at = (p0, c, p2, t) => [lerp(lerp(p0[0], c[0], t), lerp(c[0], p2[0], t), t), lerp(lerp(p0[1], c[1], t), lerp(c[1], p2[1], t), t)];
  // The t in [0, 1] where the curve's x is X.
  function tAtX(p0, c, p2, X) {
    const A = p0[0] - 2 * c[0] + p2[0], B = 2 * (c[0] - p0[0]), C = p0[0] - X;
    if (Math.abs(A) < 1e-12) return -C / B;
    const D = Math.sqrt(Math.max(0, B * B - 4 * A * C)), r1 = (-B + D) / (2 * A), r2 = (-B - D) / (2 * A);
    return r1 >= 0 && r1 <= 1 ? r1 : r2;
  }
  // The part of (p0, c, p2) from p0 to t: its control and end.
  const head = (p0, c, p2, t) => [[lerp(p0[0], c[0], t), lerp(p0[1], c[1], t)], at(p0, c, p2, t)];
  const mirror = (p) => [1 - p[0], p[1]];

  // mark_outline.dart shelterRoofCommands, plus the notch. [op, [numbers]].
  // The notch keeps the shipped roof's two slopes exactly and stops them nw
  // short of the apex, so the corner folds in between two shoulders: a V
  // down to the notch, or a dip whose bottom is round.
  function roofCommands(m, open = 1) {
    const v = m.values, ax = 0.5, ay = v.ay, ey = v.ey, w = v.w * (0.85 + 0.15 * open);
    const notch = v.notch || 0, nw = v.nw || 0, soft = v.soft || 0, gap = v.gap || 0;
    const oL = [ax - w, ey], oC = [ax - w * 0.35, ay + 0.04], oA = [ax, ay];
    const iL = [ax - w + 0.05, ey], iC = [ax - w * 0.3, ay + 0.1], iA = [ax, ay + 0.07];
    if (notch === 0 || nw === 0) {
      return [ // exactly as shipped
        ['M', [ax - w, ey]],
        ['Q', [ax - w * 0.35, ay + 0.04, ax, ay]],
        ['Q', [ax + w * 0.35, ay + 0.04, ax + w, ey]],
        ['L', [ax + w - 0.05, ey]],
        ['Q', [ax + w * 0.3, ay + 0.1, ax, ay + 0.07]],
        ['Q', [ax - w * 0.3, ay + 0.1, ax - w + 0.05, ey]],
      ];
    }
    // The shoulders: each slope up to nw from the centre.
    const [oc, oS] = head(oL, oC, oA, tAtX(oL, oC, oA, ax - nw));
    const oN = [ax, oS[1] + notch];
    // The inside follows the outside at the roof's thickness: its shoulder
    // is on the shipped inner slope, below the outer one; under a V its
    // notch is lower by the thickness across the V's arm, under a round
    // bottom (flat there) by the thickness itself.
    const arm = soft > 0 ? 1 : Math.hypot(nw, notch) / nw;
    const [ic, iS] = head(iL, iC, iA, tAtX(iL, iC, iA, ax - nw));
    const iN = [ax, oN[1] + THICK * arm];
    if (gap > 0) {
      // Two halves, cut square at the hairline.
      const along = (S, N) => [ax - gap / 2, S[1] + (N[1] - S[1]) * (1 - gap / 2 / nw)];
      const oG = along(oS, oN), iG = along(iS, iN);
      const half = (f) => [['M', f(oL)], ['Q', [...f(oc), ...f(oS)]], ['L', f(oG)], ['L', f(iG)], ['L', f(iS)], ['Q', [...f(ic), ...f(iL)]], ['L', f(oL)]];
      return [...half((p) => p), ...half(mirror)];
    }
    // The V, or the dip with a round bottom (soft: how far its curve reaches
    // out from the centre along the bottom).
    // from shoulder S through the notch N to shoulder E
    const dip = (S, N, E, k) => (soft > 0 ? [['Q', [ax - Math.sign(E[0] - S[0]) * soft * k, N[1], ...N]], ['Q', [ax + Math.sign(E[0] - S[0]) * soft * k, N[1], ...E]]] : [['L', N], ['L', E]]);
    return [
      ['M', oL], ['Q', [...oc, ...oS]], ...dip(oS, oN, mirror(oS), 1), ['Q', [...mirror(oc), ...mirror(oL)]],
      ['L', mirror(iL)], ['Q', [...mirror(ic), ...mirror(iS)]], ...dip(mirror(iS), iN, iS, 0.6), ['Q', [...ic, ...iL]],
    ];
  }

  // ---------- drawing ----------
  function roofPath(ctx, m, open = 1, f = (p) => p) {
    ctx.beginPath();
    for (const [op, v] of roofCommands(m, open)) {
      const p = [];
      for (let i = 0; i < v.length; i += 2) p.push(...f([v[i], v[i + 1]]));
      if (op === 'M') ctx.moveTo(p[0], p[1]); else if (op === 'L') ctx.lineTo(p[0], p[1]); else ctx.quadraticCurveTo(p[0], p[1], p[2], p[3]);
    }
    ctx.closePath();
  }
  function pebblePath(ctx, b, o = {}, f = (p) => p) {
    ctx.beginPath();
    blobOutline(b, o).forEach((pt, i) => { const [x, y] = f(pt); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
    ctx.closePath();
  }

  // ---------- the icon, as house_mark.dart writes it ----------
  const n3 = (v) => v.toFixed(3);
  // settledOutline: the roof's commands and the pebble's polygon as SVG
  // path data, every point (control points too) through f.
  function settledOutline(m, f = (p) => p) {
    const pt = (p) => { const [x, y] = f(p); return `${n3(x)} ${n3(y)}`; };
    let roof = '';
    for (const [op, v] of roofCommands(m)) { roof += op; for (let i = 0; i < v.length; i += 2) roof += (i ? ' ' : '') + pt([v[i], v[i + 1]]); }
    const peb = blobOutline(m.blobs.sitter);
    return [{ role: 'stroke', path: roof + 'Z' }, { role: m.roles[0] === 'stroke' ? 'form' : m.roles[0], path: 'M' + pt(peb[0]) + peb.slice(1).map((p) => 'L' + pt(p)).join('') + 'Z' }];
  }
  const CANVAS = 108, VISIBLE = 72, CONTENT = 0.9;
  function boxCentre(m) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    settledOutline(m, (p) => { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); return p; });
    return [(x0 + x1) / 2, (y0 + y1) / 2];
  }
  const toIcon = (visible, c) => (p) => [CANVAS / 2 + (p[0] - c[0]) * visible * CONTENT, CANVAS / 2 + (p[1] - c[1]) * visible * CONTENT];
  // The three SVGs house_mark.dart writes, byte for byte.
  function svgs(m, pal) {
    const c = boxCentre(m), shapes = settledOutline(m, toIcon(VISIBLE, c)), square = settledOutline(m, toIcon(CANVAS, c));
    const fill = (r) => ({ form: pal.form, stroke: pal.stroke, accent: pal.accent }[r] || pal.tile).toUpperCase();
    const head = '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="108" viewBox="0 0 108 108">\n';
    const note = `  <!-- Meditejo house mark ${m.seed} (${m.type}), generated by tools/meditejo/branding/house_mark.dart from house_mark.json. -->\n`;
    const paths = (ss, white) => ss.map((s) => `  <path fill="${white ? '#FFFFFF' : fill(s.role)}" d="${s.path}"/>\n`).join('');
    return {
      icon: `${head}${note}  <rect width="108" height="108" fill="${pal.tile.toUpperCase()}"/>\n${paths(shapes)}</svg>\n`,
      glyph: `${head}${note}${paths(shapes, true)}</svg>\n`,
      square: `${head}${note}  <rect width="108" height="108" fill="${pal.tile.toUpperCase()}"/>\n${paths(square)}</svg>\n`,
    };
  }
  return { blobOutline, roofCommands, roofPath, pebblePath, settledOutline, boxCentre, toIcon, svgs, CANVAS, VISIBLE, CONTENT };
})();
if (typeof module !== 'undefined') module.exports = Shelter;
