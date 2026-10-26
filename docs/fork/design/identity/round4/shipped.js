/* Everything Meditejo ships, which therefore gets a curated card.
 * Sounds: assets/sounds/sounds.json on fork/freesound-sounds (PR #41), plus
 * the five synth layers. Presets: lib/models/soundscape/starter_presets.dart.
 * Starter set: lib/services/library/starter_set.dart. */
const Shipped = (() => {
  const sound = (id, title, cat) => ({ id, title, cat, kind: 'sound' });
  const sounds = [
    sound('rain-terrace', 'Rain on a terrace', 'Rain'), sound('rain-umbrella', 'Rain on an umbrella', 'Rain'), sound('rain-window', 'Rain at the window', 'Rain'), sound('rain-car', 'Rain on a car roof', 'Rain'), sound('rain-indoors', 'Rain from indoors', 'Rain'), sound('rain-balcony', 'Rain on a balcony', 'Rain'),
    sound('stream', 'Mountain stream', 'Water'), sound('river', 'River', 'Water'), sound('waves', 'Small waves', 'Water'), sound('sea', 'Beach at Dellec', 'Water'), sound('ocean', 'Gentle ocean', 'Water'),
    sound('wind-trees', 'Wind in the pines', 'Wind'), sound('wind-grass', 'Wind in an open field', 'Wind'),
    sound('forest-birds', 'Forest birds', 'Forest'), sound('dawn-chorus', 'Dawn chorus', 'Forest'), sound('evening-birds', 'Evening birds', 'Forest'), sound('forest-brook', 'Forest brook', 'Forest'), sound('wood-thrush', 'Wood thrush at dawn', 'Forest'),
    sound('fire-crackle', 'Crackling fire', 'Fire'), sound('fire-stove', 'Wood stove', 'Fire'),
    sound('room-house', 'Quiet house', 'Rooms'), sound('cafe', 'Café', 'Rooms'), sound('train', 'Metro carriage', 'Rooms'), sound('laundry-room', 'Laundry room', 'Rooms'), sound('fan', 'Fan hum', 'Rooms'), sound('train-yamanote', 'Yamanote Line train', 'Rooms'),
    sound('night-meadow', 'Meadow at night', 'Night'), sound('night-insects', 'Night insects', 'Night'), sound('night-frogs', 'Frogs by a pond', 'Night'), sound('night-shore', 'Crickets by the sea', 'Night'),
    sound('noise-white', 'White noise', 'Generated'), sound('noise-pink', 'Pink noise', 'Generated'), sound('noise-brown', 'Brown noise', 'Generated'), sound('drone', 'Drone', 'Generated'), sound('binaural', 'Binaural beats', 'Generated'),
  ];
  const presets = [
    { id: 'starter-rain-forest', title: 'Rain on the forest', layers: [['rain-terrace', 0.7], ['forest-birds', 0.45], ['wind-trees', 0.3]] },
    { id: 'starter-night', title: 'Night', layers: [['night-meadow', 0.6], ['stream', 0.35]] },
    { id: 'starter-hearth', title: 'Hearth', layers: [['fire-stove', 0.6], ['fire-crackle', 0.55], ['rain-window', 0.4]] },
    { id: 'starter-shore', title: 'Shore', layers: [['waves', 0.7], ['wind-grass', 0.3]] },
    { id: 'starter-stillness', title: 'Stillness', layers: [['noise-brown', 0.55], ['drone', 0.35]] },
  ].map((p) => ({ ...p, kind: 'preset', cat: 'Presets' }));
  const starter = [
    { id: 'ds-retreat-4496', title: 'Practising the Jhānas', kind: 'course' },
    { id: 'ds-retreat-1084', title: 'The Loving Kindness (Metta) Retreat', kind: 'course' },
    { id: 'ds-retreat-1183', title: 'The Art of Concentration (Samatha Meditation)', kind: 'course' },
    { id: 'ds-retreat-1308', title: 'Samatha Meditation', kind: 'course' },
    { id: 'yt-playlist-PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3', title: 'Meditating with John Vervaeke', kind: 'course' },
    { id: 'yt-playlist-PLbmYHvGI-YSvnpbh3ppQqcG72lpw4aQdE', title: 'Qualia Mastery', kind: 'course' },
    { id: 'ds-talk-60864', title: 'Developing Piti, Developing Focus, Developing Wellbeing', kind: 'single' },
  ].map((s) => ({ ...s, cat: 'Starter set' }));
  return { sounds, presets, starter, all: [...sounds, ...presets, ...starter] };
})();
