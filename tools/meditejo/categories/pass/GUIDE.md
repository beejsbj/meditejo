# Labelling Dharma Seed retreats with practice categories

You are labelling retreats from Dharma Seed (dharmaseed.org, recorded Buddhist
talks and guided meditations) for Meditejo, an open-source meditation app.
People browse the app by kind of practice ("show me jhāna", "walking", "metta").
Each retreat may carry several categories, or none. Your labels decide what a
person finds when they tap a category, so precision matters more than recall:
a wrong label puts a retreat in front of someone looking for something else.

## The categories (use these ids exactly)

- `metta` (Metta): Loving-kindness and the brahmavihāras: compassion, joy and equanimity.
- `compassion` (Compassion): Karuṇā, tonglen and self-compassion: meeting suffering, other people's and your own, with care.
- `forgiveness` (Forgiveness): Forgiveness practice: letting go of resentment towards others and yourself.
- `relational` (Relational): Meditating with other people: Insight Dialogue, dyads and contemplative conversation.
- `sankalpa` (Sankalpa): Resolve and intention: setting a heartfelt aim and returning to it.
- `samatha` (Samatha): Calm and concentration: steadying and unifying the mind.
- `jhana` (Jhāna): The meditative absorptions, and the joy and stillness that lead into them.
- `breath` (Breath): Mindfulness of breathing and ānāpānasati.
- `tmi` (TMI): The Mind Illuminated: Culadasa's ten stages of meditation.
- `gazing` (Gazing): Trāṭaka and kasiṇa: steady gazing at a flame, a colour or a point, then at its afterimage.
- `recollections` (Recollections): The anussatis: recollecting the Buddha, Dhamma and Saṅgha, virtue, generosity and peace.
- `vipassana` (Vipassanā): Insight practice: seeing impermanence, unsatisfactoriness and not-self.
- `noting` (Noting): Mental noting: lightly labelling experience as it arises, in the Mahasi style.
- `emptiness` (Emptiness): Śūnyatā: practising with the emptiness of self and phenomena.
- `death` (Death contemplation): Maraṇasati: remembering death and impermanence to see what matters.
- `mbsr` (MBSR): Secular mindfulness programmes: MBSR, MBCT and the practices they teach.
- `open-awareness` (Open awareness): Choiceless, natural and non-dual awareness, with no single object.
- `zen` (Zen): Zazen, shikantaza and kōan practice.
- `dzogchen` (Dzogchen & Mahāmudrā): Tibetan practices of recognising the mind's own nature.
- `self-inquiry` (Self-inquiry): Asking "Who am I?" and looking for the one who is aware.
- `headless` (Headless Way): Douglas Harding's experiments: looking back at where your head should be.
- `glimpses` (Effortless mindfulness): Short glimpses of awake awareness that is already here (Loch Kelly and others).
- `nature` (Nature): Practising outdoors, with the land, the weather and other creatures as support.
- `body` (Body): Body scans, mindfulness of the body and embodied practice.
- `walking` (Walking): Walking meditation and kinhin: practising in slow, ordinary steps.
- `movement` (Movement): Yoga, qigong, tai chi and other mindful movement.
- `energy` (Energy body): Feeling and working with the subtle body: prāṇa, qi and the energy body.
- `kundalini` (Kundalini): Kundalini and kriya practice: working with energy rising through the body.
- `chakras` (Chakras): Meditating on the body's energy centres, one by one or together.
- `yoga-nidra` (Yoga nidra): Guided deep rest between waking and sleep; where a sankalpa is set.
- `focusing` (Focusing): Eugene Gendlin's Focusing: listening to the body's felt sense of a situation.
- `chanting` (Chanting): Chanting aloud: suttas, sūtras, paritta and devotional song.
- `mantra` (Mantra): Repeating a word or phrase, silently or aloud: japa, nembutsu, dhikr.
- `devotion` (Devotion): Prayer, refuge, pūjā and contemplative reading, in any tradition.
- `visualisation` (Visualisation): Practising with imagined images: light, deities, places and figures.
- `soulmaking` (Soulmaking): Rob Burbea's imaginal practice: images, eros and soul as ways of seeing.

## How to decide

- Tag a category when that practice is a **substantial, intended focus** of the
  retreat: named in the title, the stated theme of the description, or plainly
  what the talk titles teach. Not when it is mentioned in passing.
- Retreat schedules routinely say "sitting and walking meditation", "Dharma
  talks", "some metta". That alone is **not** `walking` or `metta`. Tag
  `walking` only when walking practice is a theme; `metta` when loving-kindness
  or the brahmavihāras are a stated focus or a large share of the talks.
- `vipassana`: insight or mindfulness meditation in the Theravāda / Insight
  Meditation Society style is the method (an "Insight Meditation Retreat",
  "vipassana", "satipaṭṭhāna", "mindfulness retreat" in that lineage). A
  generic Dharma-talk series with no stated method is not enough.
- `samatha` for retreats about calm and concentration; `jhana` only when the
  absorptions themselves are taught. Both may apply.
- `breath` when breathing (ānāpānasati) is the stated main object, not merely
  the usual anchor. `body` when body practice is a stated focus.
- `mbsr` only for secular mindfulness programmes (MBSR, MBCT, mindfulness-based
  approaches), `relational` for Insight Dialogue, dyads and practising together
  as the method, `nature` for retreats practised outdoors or with nature as the
  theme, `soulmaking` for Rob Burbea's imaginal practice.
- Talk series, sangha nights, study courses on suttas, retreats on ethics,
  social justice, family or daily life with no identifiable meditation practice:
  give **no categories** (an empty list). That is a fine answer.
- Most retreats get 0 to 2 categories. Use 3 only when clearly earned; 4 or more
  should be rare.
- Do not guess from a teacher's reputation alone; use what this retreat's text
  says. The teacher is context (Rob Burbea's retreats are often about jhāna,
  emptiness or soulmaking, but read which).
- Titles in other languages (German, Italian, French, Spanish, Portuguese, ...)
  count the same as English.

## Input

A JSONL file: one retreat per line with `id`, `name`, `teachers`, `talks` (how
many), `talk_titles` (a spread sample of up to 8) and `description` (cut at 600
characters).

## Output

A JSONL file with **exactly one line per input retreat, in the same order**,
and nothing else (no prose, no code fences):

{"id": 1234, "categories": ["jhana", "samatha"], "reason": "Title: 'Concentration and the Jhānas'; talks teach jhāna factors."}

`reason` is one short sentence (under 25 words) naming the evidence. For an
empty list, say why (e.g. "Weekly Dharma talks on varied topics; no practice focus.").
