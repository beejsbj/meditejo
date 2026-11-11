# Labelling Dharma Seed retreats with practice categories

You are labelling retreats from Dharma Seed (dharmaseed.org, recorded Buddhist
talks and guided meditations) for Meditejo, an open-source meditation app.
People browse the app by kind of practice ("show me jhāna", "walking", "metta").
Each retreat may carry several categories, or none. Your labels decide what a
person finds when they tap a category, so precision matters more than recall:
a wrong label puts a retreat in front of someone looking for something else.

## The categories (use these ids exactly)

- `metta` (Mettā): Wishing beings well, from the easy ones outward until no one is left out.
- `compassion` (Compassion): Letting suffering in and meeting it with care; in tonglen, breathing it in and sending ease out.
- `forgiveness` (Forgiveness): Loosening resentment, towards others and towards yourself.
- `relational` (Relational): Meditating together in conversation: pause, relax, open, and listen deeply.
- `sankalpa` (Saṅkalpa): A heartfelt resolve, planted in deep rest and returned to.
- `samatha` (Samatha): Calming and steadying the mind on one object until it settles.
- `jhana` (Jhāna): The meditative absorptions: joy and ease gathering into deep stillness.
- `breath` (Ānāpānasati): Knowing each breath in and out, in sixteen steps or in one.
- `tmi` (The Mind Illuminated): Ten stages, from a wandering mind to effortless attention.
- `trataka` (Trāṭaka): Gazing steadily at a flame or a point, then holding its image with eyes closed.
- `kasina` (Kasiṇa): A device (earth, water, fire, a colour) gazed at until its image fills the mind, towards jhāna.
- `recollections` (Anussati): Recollecting the Buddha, Dhamma and Saṅgha, virtue, generosity and peace.
- `vipassana` (Vipassanā): Seeing clearly how experience arises and passes, and holds no self.
- `noting` (Noting): Lightly labelling each experience as it comes: rising, falling, hearing, thinking.
- `emptiness` (Śūnyatā): Seeing that nothing stands on its own; everything is open, and free.
- `death` (Maraṇasati): Remembering that this life will end, so that it can be lived.
- `mbsr` (MBSR): An eight-week secular course of body scan, sitting and gentle yoga (also MBCT).
- `open-awareness` (Open awareness): Resting as awareness itself, with nothing to hold and nothing to push away.
- `zen` (Zazen): Just sitting (shikantaza), or sitting with a kōan, in the Zen way.
- `dzogchen` (Dzogchen): The Great Perfection: recognising the mind's nature as open, clear and already complete.
- `mahamudra` (Mahāmudrā): The Great Seal: resting in the mind's own nature, and seeing each thought as its play.
- `self-inquiry` (Ātma-vicāra): Asking “Who am I?” and turning towards the one who is aware.
- `headless` (Headless Way): Looking back at where your head should be, and finding open space.
- `glimpses` (Effortless mindfulness): Short glimpses of the awake awareness that is already here.
- `nature` (Nature): Practising outdoors, with land, weather and creatures as company.
- `body` (Body): Mindfulness of the body, from breath and posture to a slow scan.
- `walking` (Walking): Walking slowly and knowing each step: lifting, moving, placing.
- `movement` (Movement): Moving slowly with breath and attention.
- `energy` (Energy body): Sensing the body as a field of energy, and letting it open.
- `kundalini` (Kuṇḍalinī): The coiled energy at the base of the spine, rising through the body.
- `chakras` (Cakra): Resting attention on the body's wheels of energy, one by one.
- `yoga-nidra` (Yoga nidrā): Guided deep rest, aware between waking and sleep.
- `focusing` (Focusing): Listening to the body's felt sense of a situation until it shifts.
- `chanting` (Chanting): Chanting aloud: suttas and blessings, sūtras, devotional song.
- `mantra` (Mantra): Repeating a sacred word or phrase, often on a string of beads.
- `devotion` (Devotion): Prayer, offering and refuge, in any tradition.
- `visualisation` (Visualisation): Practising with imagined images: light, deities, places and figures.
- `soulmaking` (Soulmaking): Rob Burbea's imaginal Dharma: images, eros and soul as ways of seeing.

## How to decide

- Tag a category when that practice is a **substantial, intended focus** of the
  retreat: named in the title, the stated theme of the description, or plainly
  what the talk titles teach. Not when it is mentioned in passing.
- Retreat schedules routinely say "sitting and walking meditation", "Dharma
  talks", "some metta". That alone is **not** `walking` or `metta`. Tag
  `walking` only when walking practice is a theme; `metta` when loving-kindness
  or the brahmavihāras are a stated focus or a large share of the talks.
- `vipassana` (narrowed 2026-11-03): the retreat's **practice is insight**.
  - It is a vipassanā retreat by its own title or description, or its
    description or talk titles teach insight as the method: satipaṭṭhāna
    (the foundations of mindfulness), noting, the three characteristics,
    seeing arising and passing.
  - "Insight meditation" in a title or description counts only with that
    support: it is also the name of the movement, its centres and their
    series.
  - **Not** when insight is only a label and the stated content is something
    else (mettā, a sutta study, daily life, general Dharma talks), or when
    one insight-sounding talk sits among unrelated ones.
  - Who a retreat is for doesn't matter: a young adults', women's, LGBTQ+ or
    people-of-colour retreat that practises insight is `vipassana`.
  - With no description, the 8 sampled titles can miss the practice. A
    retreat dropped on them is re-read with every talk title (the
    2026-11-03 re-read did this for empty descriptions with more than 8
    talks).
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
