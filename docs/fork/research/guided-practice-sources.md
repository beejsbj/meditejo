<!-- Scout report, 2026-10-28 (Sonnet subagent). Extends docs/fork/content-sources.md (2026-10-14); does not repeat it. Linear BJS-586. Dharma Seed numbers come from the live API on 2026-10-28 (see "How the Dharma Seed numbers were got"). Licence quotes were read on primary pages unless marked unverified. -->

**The open guided material we already have is Dharma Seed, and it is bigger than the 2026-10-14 report suggested. Outside it there is almost nothing openly licensed. So most categories need generated sessions, and Gemini TTS or ElevenLabs gives the best calm speech while Kokoro is the free local fallback.** The API's `recording_type` field has a value `Meditation` on 6,281 of 49,071 talks (13%). That is Dharma Seed's guided-practice label. A further 2,956 talks have an empty type and could be either. Those 6,281 cover metta (about 1,200 by title), breath, body, open awareness and samatha well. Jhana guided practice exists but is thin (about 25 sessions), and noting is nearly absent (3 titles). **Culadasa has a teacher record on Dharma Seed (id 832) but no talks linked to him, so there is no TMI material there.** Everything else I checked for yoga nidra, noting, TMI, trataka and body scan is either all-rights-reserved or has no licence statement at all.

## Table: category, best open source, YouTube tier, gap

"Gap" means no usable open-licence guided audio, so it is a candidate for our own generated sessions.

| Category | Best open source (all CC BY-NC-ND via Dharma Seed unless stated) | YouTube-tier option (licence risk accepted, not verified by me) | Gap? |
|---|---|---|---|
| Metta / brahmavihāras | Dharma Seed `Meditation` type, about 1,200 title hits. Mark Nunberg (78), Jill Shepherd (63), Nathan Glyde (47), Zohar Lavie (45), James Baraz (37), Tuere Sala (35). Annual Metta Retreats (retreats 3323, 3845, 4191, 4520, 5431, 5867, 6253, 6701). dhammatalks.org 4-min guided metta. | Sharon Salzberg, Tara Brach channels (from memory) | **No** |
| Vipassanā / insight | Dharma Seed: the monthlong retreats (e.g. 3225, 2444, 2424, 3821, 2768: 32 to 35 guided sessions each). | IMS / Spirit Rock channels (from memory) | **No** |
| Sankalpa / intention | None found. Only non-guided talks on Dharma Seed. | none verified | **Yes** |
| Jhāna (guided) | Dharma Seed: Bhante Gunaratana's Jhana Retreats 2016 to 2018 (retreats 2964, 3372, 3961), Marcia Rose samatha sessions (36641, 27354, 62693), Ajahn Sucitto (63657, 64841), Tempel Smith (58047), Christina Feldman (77670), Juha Penttilä (81516), Kristina Baré (99853). Brasington jhana talks (already in the starter set). dhammatalks.org guided breath. | The starter set's Vervaeke and QRI playlists; Brasington / Ajahn Brahm talks on YouTube (from memory) | **Partly** (about 25 guided sessions, mostly instruction, few real guided jhana sits) |
| TMI (Mind Illuminated) | **None.** Culadasa is teacher 832 with 0 talks. dharmatreasure.org has an audio archive with a "Guided Meditations" category but no licence. | Culadasa / Dharma Treasure YouTube (from memory, unverified) | **Yes** (and needs permission or original scripts, see below) |
| Breath | Dharma Seed (343 title hits). dhammatalks.org 12/30/40/40-min breath meditations (CC BY-NC). UCLA Mindful (CC BY-NC-ND). | UCLA Mindful channel | **No** |
| Body / body scan | Dharma Seed (380 hits: Jill Shepherd 35, Tara Brach 34, Ajahn Sucitto 30, Bob Stahl 14). UCLA Mindful and Free Mindfulness (already scouted). | Same | **No** for plain body scan. **Yes** for a nidra-style rotation of consciousness. |
| Samatha | Dharma Seed: Marcia Rose, Oren Jay Sofer, Kim Allen, Juha Penttilä online series (retreat 5804), the starter set's retreats 1183 and 1308. | none needed | **No** |
| Open awareness | Dharma Seed (262 hits: Tara Brach 77, Jill Shepherd 22, Nathan Glyde 22, Juha Penttilä, retreat 6412 "Natural peace: Exploring Vastness of Awareness", 17 guided sessions). | Loch Kelly, Rupert Spira (from memory, copyrighted) | **No** |
| Noting | Dharma Seed has only 3 titles (98651, 88551, 77469). Unified Mindfulness: not usable (quote below). | Shinzen Young channels (`expandcontract`, `ShinzenInterviews` per a third-party list; unverified) | **Yes** |
| Yoga nidra / NSDR | Yoga Nidra Network: free to stream, 600+ recordings in 23 languages, **no licence stated**. Satyananda and iRest: restricted. | many free channels (not verified) | **Yes** |
| Walking | Dharma Seed (54 hits: Ajahn Sucitto 24). | none verified | **Mostly no** (instructions are bundled into other sessions; few clean walking sessions) |
| Kasina / trataka | None. Yogameditation.com's "Outer Tratak" is © Swami Janakananda. Insight Timer is closed. | none verified | **Yes** |

## Recommended (ranked)

**1. Dharma Seed, filtered by `recording_type == "Meditation"` (no new licence work, and it is already the app's data)**
- **Licence:** CC BY-NC-ND 4.0, covered by the earlier report. I confirmed the footer on a Dharma Seed page today: "Content on this site is licensed under a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License." (https://dharmaseed.org/teacher/832/)
- **How big:** 6,281 `Meditation` talks, 2,956 with an empty type, 38,821 `Talk`. 92% of the `Meditation` ones are English. Almost all have `publishability: general`.
- **Top teachers by `Meditation` count:** Mark Nunberg 753, Tara Brach 706, Ajahn Sucitto 356, Jill Shepherd 258, Nathan Glyde 239, Zohar Lavie 198, Ayya Santacitta 164, Tuere Sala 116, James Baraz 107, Donald Rothberg 98.
- **Guided-practice collections (retreats where most talks are guided sittings):**
  - 3012 *Weekly Dharma Series*, Mark Nunberg, 442 of 1,104 are `Meditation`.
  - 796 *IMCW Wednesday Evening Talks*, Tara Brach, 414 of 623.
  - Monthlong retreats with 30 or more guided sits each: 3225 (Adrianne Ross), 2444 (John Travis), 2424 (Heather Sundberg), 3821 (Erin Treat), 2768 (Bonnie Duran).
  - 6412 *Natural peace: Exploring Vastness of Awareness*, 17 of 26 (open awareness).
  - 5804 *Foundational Skills of Attention and Samadhi (online series)*, 14 of 21 (samatha).
  - 6262 *Vedana: A Path of Easeful Liberation*, 16 of 23.
- **Caution:** a collection is not a clean "pack". Retreat-level guided retreats mix instructions, Q&A and talks, so the app should build category packs by query (type plus title keywords plus teacher), not by retreat.
- **Caution:** Tara Brach's own feed says "All rights reserved" (earlier report), yet Dharma Seed publishes hers under CC BY-NC-ND. Dharma Seed's site licence is what the app relies on, but this is the one place the two statements disagree. Worth knowing before putting her 706 sittings in a starter pack.
- **Caution:** title keywords are noisy. "Mark Nunberg 753" is plausible; the "jhana" keyword hit 107 titles but only about 25 are really guided sits.

**2. Generate our own sessions for the "Yes" gaps (see Part B for the voice choice)**
- This is the only clean route for sankalpa, yoga nidra / NSDR, trataka and kasina, noting, TMI-style stage practices, and nidra-style body rotation.
- Write original scripts. Do not paraphrase the TMI book, the MBSR scripts (copyrighted), Satyananda's nidra script or Shinzen's "See Hear Feel" material. Practices as such are not copyrightable, but specific scripts and some names are protected (trademark status of "Unified Mindfulness" and "iRest" is stated below). Whether a generic "noting" or "rotation of consciousness" script would infringe is a legal call I did not make.
- We can then license our own audio however we like (e.g. CC BY-SA, matching AGPL's spirit), subject to the voice licence in Part B.

**3. Yoga Nidra Network: ask, do not assume**
- The library page says it is offered "FREELY to all who visit this website" and that the audio files are "available for you to stream as you wish for no charge" (https://www.yoganidranetwork.org/downloads). It states **no licence**, and the page said teachers may have their own terms. 600+ recordings in 23 languages.
- A free app streaming this would be a gamble, not a licence. Email info@yoganidranetwork.org. Treat the answer as the licence.

**4. Dharma Treasure (Culadasa's organisation): ask**
- https://dharmatreasure.org/audio-archive/ lists the categories "Every Recording," "Questions and Answers," "Teaching Retreats," "Intensive Meditation Retreats," "Guided Meditations," "TCMC Thursdays," and "Uposatha Days." The only notice is "Copyright © 2026 by Dharma Treasure." No licence, no sharing terms. Contact given on the home page: retreats@dharmatreasure.org.
- This is the only plausible official source of Culadasa's guided TMI sessions, and it has a "Guided Meditations" category. I did not see the file list or hosting (not stated on the page).
- **The book's copyright holder:** I could not confirm it from a primary page. Dharma Seed's bio of Culadasa gives the publisher as "Dharma Treasure Press, October 6, 2015," and trade editions exist from Touchstone/Atria (per search listings). The copyright page of a copy of the book is the definitive source. **Unverified.**

## Not usable, or not verified

- **Unified Mindfulness (Shinzen Young):** https://www.unifiedmindfulness.com/terms-of-use says "This site is provided solely for non-commercial, personal use" and "the Content may not be copied, distributed, republished, uploaded, posted, or transmitted in any way without the prior written consent of our Company." It even forbids linking without permission ("hyperlink to this site"). Shinzen's own PDF carries "©2011-2017 Shinzen Young • All rights reserved". Reject. Ask only if Burooj wants noting by Shinzen specifically.
- **Brightmind** (app by Shinzen's students, 8 free intro meditations per a search listing): the URL I tried returned 404, so I could not read any terms. **Unverified**, likely proprietary.
- **Satyananda yoga nidra:** no copyright or reuse terms found. A trademark record shows SATYANANDA YOGA NIDRA registered for pre-recorded audio and visual recordings, owned by IYFM Ltd (Justia). The school's centenary release of recordings in 108 languages is an app/site release with no stated reuse rights. Treat as copyrighted and trademarked. **Confirmed that there is no open licence; the exact owner is unverified.**
- **iRest (Integrative Restoration):** the Institute says it is "sole and exclusive owner of the copyrights, trademarks, and intellectual property" and licenses only trained teachers (https://shop.irest.org/pages/intellectual-property-standard-use-license-agreement). Registered names may not be used. Reject. Do not use "iRest" or "Integrative Restoration" in any title. (I could not load the guidelines page itself; 404 after redirect.)
- **UCSD Center for Integrative Health body scans:** search listings say each page carries "all rights reserved." I did not open the pages. **Unverified**, consistent with the earlier report's "no licence page".
- **Insight Timer:** closed catalogue. Skip.
- **Internet Archive and Wikimedia Commons:** I queried both for guided meditation. IA returns scattered one-off uploads, a few CC BY-NC-ND teacher recordings (Swami Tattvavidananda guided meditations 16 and 26, `SwamiTattvavidananda-GuidedMeditation16`, CC BY-NC-ND 3.0 US) and mostly music. Commons has German-language meditation files and music. No coherent collection. Skip, as the earlier report found for IA.
- **TMI community material:** I found no Dharma Treasure, Tasshin or r/TheMindIlluminated guided-audio collection with a licence. Reddit could not be fetched. **Unverified**: the subreddit wiki may list stage-by-stage audio, but community recordings would need each creator's permission.
- **Kasina / trataka:** no guided kasina audio found anywhere. Yogameditation.com "Outer Tratak" is © Swami Janakananda. Skip.
- **YouTube channel names above:** I could not fetch YouTube (the search page returned only footer text). Channel names marked "from memory" are my recollection, not checked. Check before building playlists.

## Part B: TTS voices for generating our own sessions

### Short answer
- **Quality pick (paid, pennies per session): Gemini TTS via the Gemini API.** Style prompting handles "speak slowly", inline `<short pause>`/`<long pause>`, and Google's terms say it won't claim ownership. Cheapest per minute, and the free tier works for drafts (with the data caveat below).
- **Runner-up: ElevenLabs**, needs a paid plan for commercial use, and its newest models cannot use SSML break tags. Fine voices, fiddly pause control.
- **Free, offline, safe licence: Kokoro** (Apache-2.0 code and weights). Calm enough, 54 voices, but no pause markup (split text on newlines and insert silence ourselves).
- **Best newer open model to try: Qwen3-TTS** (Apache-2.0, "VoiceDesign" takes a natural-language voice description). I could not confirm pause or speed control from the model card, so treat as a candidate to listen to.
- **Avoid for shipping:** F5-TTS weights (CC-BY-NC), Voxtral TTS (CC BY-NC), Higgs TTS 3 (research / non-commercial licence), Orpheus (Llama terms on weights), VibeVoice (MIT licence but research-only caution), Piper (GPL code, per-voice licences).

### Comparison

| | Calm, slow, warm | Pause control | Licence of output | Cost | Notes |
|---|---|---|---|---|---|
| **Gemini 3.8 Flash TTS** (`gemini-3.8-flash-tts`) | Yes, via style prompt ("speaking slowly", pacing, volume) | Inline `<short pause>`, `<long pause>`, ellipses | Google "won't claim ownership" | Paid: $0.50 / 1M text tokens, $9.00 / 1M audio tokens (promo "through December 31, 2026"). Free tier available. | 30 prebuilt voices plus an Extended Voice Library; 130+ languages. |
| **ElevenLabs** | Yes (voices good, `speed` 0.7 to 1.2) | `<break time="x.xs" />` only on older models; v3/v4 use audio tags and ellipses | You keep output rights; **paid plan needed for commercial use** | Free 10,000 credits; Creator $11/mo for 121,000 credits; 1 credit per character | Free plan is non-commercial. |
| **Kokoro 82M** | Reasonable, flat | None; split on `\n+` | Apache-2.0 code and weights | Free, CPU-capable | 54 voices, 8 languages. |
| **Qwen3-TTS** | VoiceDesign by text description (unverified for pace) | Not documented on card | Apache-2.0 | Free; GPU helps | 10 languages. |
| **Chatterbox** | OK; `cfg_weight` lower slows pace | None; `[laugh]`-style tags only on Turbo | MIT | Free | Embeds Perth watermark in all output. |
| **Piper** | Basic | None found | Code GPL-3.0; voices vary | Free, very light | Voices may be restrictive. |
| **F5-TTS** | n/a | Not documented | **Weights CC-BY-NC** | Free | Reject for shipping. |

### Gemini TTS (Google AI Studio / Gemini API)
- **Ownership.** https://ai.google.dev/gemini-api/terms ("Use of Generated Content"): "Some of our Services allow you to generate original content. Google won't claim ownership over that content." Google may generate similar content for others. The terms also say applicable law may require attributing generated content to end users when it appears in an API response (paraphrase of the page; I did not read the original wording). You are responsible for your own use.
- **Restriction relevant to us.** "You may not use the Services to develop models that compete with the Services (e.g., Gemini API or Google AI Studio)." Making meditations is fine. Training our own TTS on Gemini output is not.
- **Data.** Unpaid services: "Google uses the content you submit to the Services and any generated responses" to improve products, and human reviewers may read them. Paid: Google "doesn't use your prompts or responses to improve our products." For public meditation scripts this does not matter. Do not feed it anything private.
- **Medical.** The page (summary) says the Services may not be used in clinical practice or to provide medical advice. Our sessions are meditation practices, not treatment. Avoid claims like "treats insomnia/trauma" in generated content or titles.
- **Prices** (https://ai.google.dev/gemini-api/docs/pricing, per 1M tokens, 2026-10-28):
  - `gemini-3.8-flash-tts`: free tier "Free of charge"; paid "$0.50 (text) through December 31, 2026" and "$9.00 (audio) through December 31, 2026."
  - `gemini-3.1-flash-tts-preview`: paid $1.00 text, $20.00 audio.
  - `gemini-2.5-flash-preview-tts`: paid $0.50 text, $10.00 audio.
  - `gemini-2.5-pro-preview-tts`: free tier "Not available"; paid $1.00 text, $20.00 audio.
  - The 3.8 prices are marked as a promotion ending 2026-12-31. What it costs after that is **not stated**.
  - Rough cost, **an estimate resting on an assumption I did not verify** (audio output at about 25 tokens per second, which is Gemini's usual audio rate): a 30-minute session is about 45,000 audio tokens, so about $0.40 at $9 per 1M and about $0.90 at $20 per 1M.
- **Style prompting** (https://ai.google.dev/gemini-api/docs/speech-generation): put "emotions, delivery style, prosody, pacing, and volume that apply across an entire turn" in the `style` field; "Place momentary non-speech vocal bursts or pauses directly inside the transcript using angle brackets" (e.g. `<short pause>`, `<long pause>`); ellipses and dashes create hesitation; capitals emphasise.
- **Limits.** Text in, audio out. Up to 2 speakers. The page states no maximum audio duration, so long sessions probably need to be generated in chunks and joined. **Unverified**: consistency of the voice across chunks.
- **SynthID.** The speech page does not mention a watermark. **Unverified** whether output is watermarked.

### ElevenLabs
- **Ownership.** Terms of use, section 4(c)(ii): "Except as expressly set forth herein, as between you and ElevenLabs, you retain all rights in and to your Output." (https://elevenlabs.io/terms-of-use)
- **Commercial use.** Section 1(c): "(i) if you access or use our Services free of charge (such a user, a "Free User"), you may only use the Services for non-commercial purposes; (ii) if you access or use our Services through a paid subscription plan (such a user, a "Paid User"), you may use the Services for commercial purposes, but in either case, your access and use of the Services and any Output must still comply with the Prohibited Use Policy." Non-commercial use also requires "a personal e-mail address."
- **Is a free GitHub app "commercial"?** Probably not (no sale), but ElevenLabs does not define it on the pages I read, and a project published by a "personal" account is murky. A paid month avoids the question. **Whether output generated on a paid plan stays commercially usable after cancelling is unverified**; their help-centre article returned 403.
- **Free-tier attribution.** The pricing page and terms I read state no attribution requirement. Older ElevenLabs material has required it; **unverified**, since the help article was blocked.
- **Pricing** (https://elevenlabs.io/pricing): Free $0, 10,000 credits per month, commercial licence not listed. Starter: "Start with 30,000 credits for only $1" (the table shows $1 first-month discount; the regular Starter price was not clear from the page). Creator $11 per month (first month $22 in the table), 121,000 credits, Commercial License included. Pro $99, 600,000 credits. "Credits are shared across every product"; text to speech costs 1 credit per character per the page summary. A 20-minute spoken session is roughly 15,000 to 20,000 characters, so about one Creator-plan month covers 6 to 8 sessions, before retakes.
- **Pauses and pace** (https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices): "Eleven v4 and Eleven v3 do not support SSML break tags." For those, "Use audio tags, punctuation (ellipses), and text structure to control pauses and pacing." `<break time="x.xs" />` works on older models, but "Using too many break tags in a single generation can cause instability." Speed: "Values below 1.0 will slow the voice down, to a minimum of 0.7." Meditation needs long silences, so we would add silence in an audio editor anyway.

### Open models (code and weights checked separately)

| Model | Code licence | Weights licence | Verdict |
|---|---|---|---|
| **Kokoro 82M** v1.0 | Apache-2.0 (`hexgrad/kokoro`, LICENSE read) | `apache-2.0` (Hugging Face metadata). Card: "trained exclusively on permissive/non-copyrighted audio data and IPA phoneme labels." | **Safe.** Voice data is addressed on the card: public domain / Apache / MIT audio plus two CC BY sets (Koniwa `tnc` CC BY 3.0, SIWIS CC BY 4.0) and synthetic audio from closed TTS providers. If shipping the weights or audio, credit CC BY sources (attribution detail unverified). |
| **Qwen3-TTS** (1.7B / 0.6B, Base, CustomVoice, VoiceDesign) | Apache-2.0 | `apache-2.0` (Hugging Face tags) | **Candidate.** Card: "covers 10 major languages" and "speech generation driven by natural language instructions for flexible control over timbre, emotion, and prosody." Training data licence and pause control not stated on the card (tech report arXiv 2601.15621 not read). |
| **Chatterbox** (Resemble AI) | MIT | `mit` | Safe licence. Output includes Perth watermark ("imperceptible neural watermarks that survive MP3 compression"). Variants: Turbo 350M and Nano 110M (English), Multilingual V3 500M (23+ languages). Training data not described ("sourced from freely available data on the internet"). |
| **Piper** (`OHF-Voice/piper1-gpl`) | GPL-3.0 | per voice | Docs: "Piper is intended for personal use and text to speech research only." and "Some voices may have restrictive licenses, however, so please review them carefully!" Repo is seeking maintainers. Skip unless nothing else works. |
| **F5-TTS** | MIT | **CC-BY-NC** | "The pre-trained models are licensed under the CC-BY-NC license" (due to Emilia training data). Reject. |
| **Orpheus 3B** | Apache-2.0 | `apache-2.0` on the repo tag | Search sources say the Llama backbone brings Llama licence terms; I did not read the model card. **Unverified.** English only. |
| **VibeVoice 1.5B** (Microsoft) | MIT | `mit` | Search sources say the card restricts it to research and advises against commercial use. **Unverified**; reject on risk. |
| **Voxtral TTS** (Mistral) | n/a | CC BY-NC 4.0 (search sources) | Reject. |
| **Higgs TTS 3** (Boson AI) | n/a | "Boson Higgs TTS 3 Research and Non-Commercial License" | "Production, hosted APIs, embedding in a product/service, or reselling the model requires a separate commercial license." Reject. |

- All of these are free to run for our own pre-generated audio. The licence only bites if we ship the model in the app. We do not plan to. What we ship is audio, so the risk is "what rights do we have in the output." Apache and MIT models give us the clearest answer.
- **Voice cloning is out of scope.** Do not clone a real teacher's voice (consent, and Dharma Seed's ND clause).
- **A calm voice is a listening test, not a licence question.** None of these cards makes claims about meditation tone. I did not generate samples. A 10-minute listening test per candidate is the next step.

## Open points for Burooj

1. **Dharma Seed first, or generate first?** The cheapest thing is a "guided practice" feed over the `Meditation` type with category filters. Decide whether the starter set gets category packs built from queries (my suggestion: Metta, Breath, Body, Open awareness, Samatha) before any TTS work.
2. **Which gaps are worth generating?** Sankalpa, yoga nidra / NSDR, noting, trataka / kasina and TMI-style stages. My suggestion: nidra / NSDR, sankalpa and a body-rotation first, since there is the most listener demand and no open source. Noting and trataka are short and cheap to try.
3. **TMI.** Two options: email Dharma Treasure (retreats@dharmatreasure.org) about their "Guided Meditations" category, or write original stage practices. Calling them "Mind Illuminated stage N" could invite trademark or book-rights questions; "stage-based attention training" avoids it. I did not verify who holds the TMI trademark.
4. **Voice.** Gemini 3.8 Flash TTS for the finished voice, Kokoro for drafts? That means a Google account and pennies. Silence between phrases would be added by our own tooling, not the model. A listening test of 2 to 3 voices on one 3-minute script settles it.
5. **Licence for our own audio.** If we generate, pick a licence for it (suggest CC BY-SA 4.0 or the same as the app, AGPL has no standard audio equivalent). Gemini's terms say Google may generate similar content for others, so exclusivity is not available.
6. **Dharma Seed's `Meditation` label is not guaranteed.** Decision 11 already says labels are soft. 2,956 talks have an empty type, some of them guided.
7. **Tara Brach's 706 sittings.** Dharma Seed lists them under CC BY-NC-ND while her own feed says "All rights reserved." Do we include her in the starter packs? Your call.

## How the Dharma Seed numbers were got

- Unofficial API as in BRIEF decision 3: 1 request for teachers (detail=1), 1 for retreats (detail=1), 1 for the talk id list, then 10 chunked calls of 5,000 items each with a 3-second pause (a single detail=1 call for all talks times out with a 504). About 13 calls total, no HTML crawling. The data is in `/tmp` scratch files, not saved to the repo.
- The `teacher/?search=` and `/teacher/832/` HTML pages load their lists with JavaScript, so Culadasa was found via the API's teacher list (`id 832`, bio gives *The Mind Illuminated* publisher as Dharma Treasure Press). No talk in the 49,071 has 832 in `teachers`.
- Category counts are keyword matches over titles of `Meditation`-type talks (e.g. "metta|loving|brahma", "jh[aā]na|kasina|nimitta|piti|samatha"). They are indicators, not curated sets. Expect false positives such as the word "body" in unrelated titles.
- Teacher names in the talk list were taken from the API's teacher record.

Sources: [Dharma Seed](https://dharmaseed.org/), [Dharma Treasure audio archive](https://dharmatreasure.org/audio-archive/), [Unified Mindfulness terms](https://www.unifiedmindfulness.com/terms-of-use), [Yoga Nidra Network downloads](https://www.yoganidranetwork.org/downloads), [iRest licence](https://shop.irest.org/pages/intellectual-property-standard-use-license-agreement), [Gemini API terms](https://ai.google.dev/gemini-api/terms), [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing), [Gemini speech generation](https://ai.google.dev/gemini-api/docs/speech-generation), [ElevenLabs terms](https://elevenlabs.io/terms-of-use), [ElevenLabs pricing](https://elevenlabs.io/pricing), [ElevenLabs best practices](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices), [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign), [Chatterbox](https://github.com/resemble-ai/chatterbox), [Piper](https://github.com/OHF-Voice/piper1-gpl), [F5-TTS](https://github.com/SWivid/F5-TTS), [Higgs TTS 3](https://huggingface.co/bosonai/higgs-tts-3-4b).
