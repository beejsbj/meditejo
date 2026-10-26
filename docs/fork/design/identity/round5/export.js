/* The curated_art.json format, shared by curate.mjs and the page's export.
 * Round 5 adds bells: each has a card and an icon, picked separately, and
 * carries its five sound controls and its asset. */
const Export = (() => {
  // picks: { itemId: candidateIndex, bellId: { card, icon } }. Unknown ids
  // are ignored.
  function curated(picks) {
    const items = {};
    for (const item of Shipped.all) {
      if (!(item.id in picks)) continue;
      const i = picks[item.id], comp = Compose.candidates(item, 8)[i];
      items[item.id] = { title: item.title, kind: item.kind, pick: i, ...Compose.freeze(comp) };
    }
    for (const b of Prims.bell.SHIPPED) {
      const pk = picks[b.id];
      if (!pk) continue;
      const card = Compose.candidates({ id: b.id, kind: 'bell' }, 8)[pk.card], icon = Compose.candidates({ id: b.id, kind: 'bellicon' }, 3)[pk.icon];
      items[b.id] = { title: b.title, kind: 'bell', asset: b.asset, preset: b.preset, knobs: card.figure.p.knobs, pick: pk, card: Compose.freeze(card), icon: Compose.freeze(icon) };
    }
    return {
      format: 'meditejo-curated-art/1',
      generator: 'identity round 5 (docs/fork/design/identity/round5)',
      note: 'Shipped items only. Each entry is a frozen composition: rebuild it from these params, not from the generator, so later generator changes cannot alter what ships. Bells carry a card and an icon, and the five sound controls their figure is drawn from.',
      items,
    };
  }
  return { curated };
})();
