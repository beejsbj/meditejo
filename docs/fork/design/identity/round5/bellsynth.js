/* A sketch of custom-bell synthesis for the page's knob demo (BJS-587's
 * prototype). It uses tools/meditejo/generate_bells.py's model: each mode is a
 * decaying sine, split into two beating halves, with a filtered noise strike.
 * It starts from a shipped bell's own modes (BellData, read from the generator
 * by bell_params.py) and moves them with the five controls:
 *
 *   pitch    every mode's frequency, by the same ratio
 *   bright   the upper modes' level, so their share of the ring energy matches
 *   ring     every mode's decay, by the same ratio
 *   strike   the strike's low-pass (300 Hz soft .. 10 kHz hard) and level
 *   shimmer  every mode's beat, by the same ratio
 *
 * A browser sketch, not the shipped sound: it leaves out the pitch glide of the
 * wooden fish and the gong's noise wash, and does not match loudness. */
const BellSynth = (() => {
  'use strict';
  const TWO_PI = Math.PI * 2;
  function modesFor(preset, kn) {
    const d = BellData[preset], ref = d.knobs, fk = kn.pitch / ref.pitch, tk = kn.ring / Math.max(ref.ring, 1e-3);
    const ms = d.modes.map((m) => ({ ...m, f: m.f * fk, tau: m.tau * tk, beat: ref.shimmer > 0 ? m.beat * kn.shimmer / ref.shimmer : kn.shimmer * Math.sqrt(m.f / ref.pitch) }));
    const main = ms.reduce((a, b) => (b.a > a.a ? b : a)), up = (m) => m.f > main.f * 1.05, E = (m) => m.a * m.a * m.tau;
    const lo = ms.filter((m) => !up(m)).reduce((s, m) => s + E(m), 0), hi = ms.filter(up).reduce((s, m) => s + E(m), 0);
    if (hi > 0) { const b = Math.min(Math.max(kn.bright, 0.001), 0.98), g = Math.sqrt((b * lo) / ((1 - b) * hi)); ms.forEach((m) => { if (up(m)) m.a *= g; }); }
    return { ms, main };
  }
  function render(preset, kn, rate = 44100) {
    const d = BellData[preset], { ms, main } = modesFor(preset, kn);
    const seconds = Math.min(12, Math.max(0.35, main.tau * 5 + 0.3)), n = Math.round(rate * seconds), out = new Float32Array(n);
    for (const m of ms) {
      if (m.f >= rate * 0.46) continue;
      const halves = m.beat ? [[m.f - m.beat / 2, m.a * 0.7], [m.f + m.beat / 2, m.a * 0.3]] : [[m.f, m.a]];
      const decay = Math.exp(-1 / (rate * m.tau)), grow = m.rise ? Math.exp(-1 / (rate * m.rise)) : 0, last = Math.min(n, Math.floor(13.8 * m.tau * rate) + 1);
      for (const [f, a] of halves) {
        // a sine by recurrence: y[i] = 2 cos(w) y[i-1] - y[i-2]
        const w = TWO_PI * f / rate, c2 = 2 * Math.cos(w), ph = (m.f * 7.3) % TWO_PI;
        let y1 = Math.sin(ph - w), y2 = Math.sin(ph - 2 * w), env = a, g = 1;
        for (let i = 0; i < last; i++) { const y = c2 * y1 - y2; y2 = y1; y1 = y; out[i] += env * (grow ? 1 - g : 1) * y; env *= decay; g *= grow; }
      }
    }
    const h = d.hit, ref = d.knobs.strike, lp = 300 * Math.pow(10000 / 300, kn.strike), k = 1 - Math.exp(-TWO_PI * lp / rate), level = h.level * (0.6 + 0.8 * kn.strike) / (0.6 + 0.8 * ref);
    let y = 0, z = 0, seed = 7;
    const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed / 2147483647) * 2 - 1; };
    for (let i = 0, N = Math.min(n, Math.round(rate * 0.15)); i < N; i++) { const t = i / rate; y += k * (rnd() - y); z += k * (y - z); out[i] += z * 1.6 * Math.exp(-t / h.tau) * Math.min(1, t / Math.max(h.attack, 1e-4)) * level; }
    let peak = 1e-9; for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(out[i]));
    const fade = Math.round(n * 0.15);
    for (let i = 0; i < n; i++) { out[i] *= 0.7 / peak; if (i > n - fade) out[i] *= 0.5 * (1 + Math.cos(Math.PI * (i - (n - fade)) / fade)); }
    return out;
  }
  let ac = null, playing = null;
  function play(preset, kn) {
    try {
      ac = ac || new (window.AudioContext || window.webkitAudioContext)();
      if (ac.state === 'suspended') ac.resume();
      const data = render(preset, kn, ac.sampleRate), buf = ac.createBuffer(1, data.length, ac.sampleRate);
      buf.copyToChannel(data, 0);
      if (playing) { try { playing.stop(); } catch {} }
      const src = ac.createBufferSource(), g = ac.createGain();
      src.buffer = buf; g.gain.value = 0.55; src.connect(g).connect(ac.destination); src.start(); playing = src;
    } catch {}
  }
  return { modesFor, render, play };
})();
