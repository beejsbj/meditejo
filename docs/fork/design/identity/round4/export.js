/* The curated_art.json format, shared by curate.mjs and the page's export. */
const Export = (() => {
  // picks: { itemId: candidateIndex }. Unknown ids are ignored.
  function curated(picks) {
    const items = {};
    for (const item of Shipped.all) {
      if (!(item.id in picks)) continue;
      const i = picks[item.id], comp = Compose.candidates(item, 8)[i];
      items[item.id] = { title: item.title, kind: item.kind, pick: i, ...Compose.freeze(comp) };
    }
    return {
      format: 'meditejo-curated-art/1',
      generator: 'identity round 4 (docs/fork/design/identity/round4)',
      note: 'Shipped items only. Each entry is a frozen composition: rebuild it from these params, not from the generator, so later generator changes cannot alter what ships.',
      items,
    };
  }
  return { curated };
})();
