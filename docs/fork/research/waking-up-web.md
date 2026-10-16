# Waking Up: UI/UX research from public web sources

Researched 2026-10-16 for Meditejo. This covers what a hands-on tour cannot: history, stated rationale, release notes, reviews. It is meant to be read alongside the phone tour of the real Android app.

Confidence key: **High** = Waking Up's own pages or store listings, consistent across sources. **Med** = a single official page, or several third-party sources that agree. **Low** = one third-party source, a marketing blog, an aggregator, or something I inferred.

## Access limits and caveats

- **Reddit (r/WakingUp) could not be reached.** The fetch tool is blocked there, and search refuses the domain. The "complaints" section therefore rests on Google Play reviews and developer replies, blog reviews, and one aggregator. It has no first-hand Reddit threads. Treat community sentiment as under-sampled.
- **Mobbin:** `mobbin.com` pages returned 403 to the fetch tool, so I did not view them and did not sign in. Search results show three public Waking Up iOS entries, described only from search snippets:
  - [Onboarding flow, 12 screens](https://mobbin.com/explore/flows/76fb3fc0-a8e4-41b5-904d-1f108dca056e): account creation, choosing an experience level, a free-trial offer.
  - [Turning on quotes flow, 7 screens](https://mobbin.com/flows/35f82d5c-afc3-4d6a-b14d-340ff6bbadee?tab=screens): enabling the Daily Quote and notification preferences.
  - [Playlist reorder screen](https://mobbin.com/explore/screens/5f74befd-72a9-408f-985f-cedbc55649b2).
  - Burooj can open these himself; they are the most direct visual reference.
- Some third-party review sites are AI-written SEO pages (the productivity-apps and lifestack pages in particular). I mark claims from them Low.
- **Platform versions:** App Store notes use 3.x. APKMirror's older Android history uses 2.x, up to 2.31.0 in July 2024. The current Play "What's new" text is identical to iOS 3.27, so the platforms now ship the same feature set. The Android-specific differences I found are minor (see Platform differences).

## 1. Navigation and information architecture

**Current structure: four bottom tabs, Home, Explore, My Library, More.** (High)

Source: the official help article [How is the app organized?](https://help.wakingup.com/article/76-how-is-the-app-organized).

| Tab | What it holds |
|---|---|
| **Home** | User-customizable surface: Daily Meditation, Moment, Quote, Daily Wisdom queue, optional Meditation Timer, Continue Listening, pinned Series (My List). Sleep section was added here in 3.15. |
| **Explore** | Content entry point. Three top-level sections, **Practice / Theory / Life**. Sam Harris conversations and Q&As sit at the top. Search with filters. Carousels such as guided meditations and contemplations. |
| **My Library** | Saved and downloaded series, playlists, and tracks. User-made playlists. |
| **More** | Profile, notifications and reminders, settings, messages. Links to the merch store and Community, if eligible. |

**How it changed** (reconstructed from release notes and the official [A New Way to Explore](https://wakingup.com/features/explore) page; dates are from store notes unless marked):

- **2018:** launch with Sam Harris. A Metalab case study ("[A practice in patience](https://archive.metalab.com/projects/waking-up)") credits Metalab with the original iOS app. It says two onboarding experiences were merged into one. (Med)
- **2021:** full UI redesign by the agency Partner (details in section 7). (Med)
- **Pre-2024 "New Way to Explore" redesign. Date not found.** Official copy says:
  - Home became "much simpler", keeping Daily Meditation, Daily Wisdom, and Continue Listening.
  - Practice, Theory and Life moved into Explore, along with Conversations and Q&A.
  - Search moved from Home to the top of Explore.
  - My Library was promoted into the bottom bar "in response to user feedback".
  - The Meditation Timer, messages and settings sat under More.
  - Library content was regrouped "into more specific collections so you can find what you want faster".
  - (High on content, no date.)
- **Jun to Jul 2023 (2.17, 2.18):** "Reflections" gets a button on the home screen, rolled out to all members. Search gains speaker search and in-session word search. "Mark as unplayed" returns. ([2.17.0](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-17-0-release/), [2.18.0](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-18-0-release/)) (High)
- **Nov 2023 (2.22):** Daily Quote, widgets, and the Total Minutes vs Practice Minutes split ([2.22.0](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-22-0-release/)). (High)
- **Dec 2023 (2.24.1):** onboarding updates ([note](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-24-1-release/)). (High)
- **Mar 2024 (2.26.0):** unlimited user playlists, team-curated playlists, My Library redesigned so saved sessions collect in one playlist and saved/downloaded series show together ([note](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-26-0-release/)). (High)
- **Jul 2025 (3.13.1):** home becomes customizable. Users add or remove Moment, Reflection, Quote and Meditation Timer. The timer thus moved from the More tab to an optional Home module. (High; the timer's old location comes from the older explore page, so the move is inferred)
- **Oct 2025 (3.15, 3.16):** Sleep section on Home (Sleep Talks plus Guided Sleep Meditations). Library-wide filters for length, speaker and "newly added".
- **Feb to Mar 2026 (3.19):** My List, up to three pinned series on Home, with better completed/unplayed tracking.
- **Jun to Jul 2026 (3.22, 3.23):** redesigned Meditation Timer and per-section background sounds. "Reflections" renamed **Daily Wisdom**, with a filterable feed. CarPlay support.
- **Aug 2026 (3.25):** new **Profile**. It shows total practice minutes, this week's activity, and top teachers and sections. History, Messages and member stats moved into it.

All 3.x entries are from the [App Store listing](https://apps.apple.com/us/app/waking-up-meditation-wisdom/id1307736395), whose release notes I parsed from the page. (High)

**Two small inconsistencies in official copy.** Search is "upper-right" in the help article but "top left" in the 3.16 notes. The help article still says Daily Wisdom/Reflection in places. Neither affects the design read.

**Trend worth noticing:** the tab bar has stayed at four for a long time. Growth has gone into customizable Home modules, not new tabs. (Med, my inference from the notes)

## 2. Home screen

- **Home is a user-assembled shelf, not an algorithmic feed.** (High, [help 76](https://help.wakingup.com/article/76-how-is-the-app-organized) and the [3.13.1 notes](https://apps.apple.com/us/app/waking-up-meditation-wisdom/id1307736395))
  - A **Customize** button at the top opens a panel to switch modules on or off: Moment, Quote, Daily Wisdom, Meditation Timer, My List.
  - Fixed anchors are the Daily Meditation and **Continue Listening**, which resumes any series or playlist you have started.
- **Daily Meditation:** one new Sam Harris session per day. On first start of each one it offers an extend-the-session prompt (see section 5).
- **My List** (3.19):
  - Pins up to **three Series** to the top of Home.
  - Unlike Continue Listening, which fills itself, you choose what goes there. Pin from a Series page, a Series card menu, or the **Recommended** list in the My List edit panel. ([help 371](https://help.wakingup.com/article/371-what-is-my-list))
  - Recommended items are described as "curated". I found no evidence of a personalisation algorithm. (Med)
- **Daily Wisdom queue:** clips from about 30 seconds to over 10 minutes, curated from across the app ([help 311](https://help.wakingup.com/article/311-what-are-reflections)).
  - Swipe left or press forward to skip.
  - A **Filter Queue** control narrows by teacher or speaker.
  - Save a clip, or jump to its source series.
  - Everything played lands in History.
  - It works as a low-effort entry point that also advertises the deeper library.
- **Moment:** a short audio reflection, shown on Home or pushed in a time window the user picks, by push, email, or both ([help 81](https://help.wakingup.com/article/81-what-are-moments)).
- **Daily Quote:** on Home, as push or email in a user-chosen window, or as an OS widget ([help 326](https://help.wakingup.com/article/326-what-is-the-daily-quote)). 100 new quotes were added in 3.27.
- **Offline:** when you have no connection, a carousel on Home shows downloaded content. It hides when you are online ([help 336/115 summary](https://help.wakingup.com/article/115-can-i-download-content-locally-and-play-it-offline)).
- **Home-screen widgets (OS level):** Daily Meditation, Daily Quote, My List, Introductory Course. The Intro Course widget opens "the next track" in one tap ([help 370](https://help.wakingup.com/article/370-what-is-a-widget-and-how-do-i-use-it)). (High)
- One 2020 reviewer ([frimmin](https://www.frimmin.com/2020/08/)) found opening on "Daily Meditation" confusing as a newcomer and recommended going to "Start here", then Practice, then the Intro Course. This was a pre-redesign layout, so it is stale. It does show why the later home became calmer and why first-run guidance matters. (Low)

## 3. Courses and series

- **Structure** (High, [help 76](https://help.wakingup.com/article/76-how-is-the-app-organized), the [Explore page](https://wakingup.com/features/explore)):
  - Content is **Series**: ordered tracks inside Practice, Theory or Life. Also Conversations and Q&As, and playlists that mix content.
  - Explore filters by type: Meditation, Lesson, Exercise, Q&A, Contemplation, Talk, Conversation. It also filters by duration (3.16 added speaker and "newly added").
- **Sequencing and progress:**
  - "Next track" logic is explicit in the Intro Course widget and in Continue Listening.
  - 3.19 notes: "we've improved how we track completed content, making it easier to visualize your progress, and to mark series and tracks as played and unplayed". (High)
  - Audio position is remembered. The account-deletion article lists "progress through audio tracks" among stored data ([help 327](https://help.wakingup.com/article/327-how-do-i-delete-my-account)).
  - One aggregator reports the resume position being lost on long talks (Low, see section 10).
- **Introductory Course** ([help 77](https://help.wakingup.com/article/77-whats-the-introductory-course), [help 92](https://help.wakingup.com/article/92-what-s-the-best-way-to-build-a-consistent-meditation-practice)):
  - It is a 28-day course (store listings), about 10 minutes a session, found in Practice under Explore.
  - Help recommends that *both beginners and experienced practitioners* finish it.
  - The pairing is practice sessions plus short theory lessons ([wakingup.com](https://www.wakingup.com/)).
  - Order is fixed, the same for everyone. A critical review: it "hits a wall" for free users after five days, and by about Day 14 the language is "entirely too advanced" for true beginners ([ixcoach](https://www.ixcoach.com/learn/waking-up-app-review-2026), Low-Med).
  - 3.27 only just brought **Autoplay, Interlude and Custom Practice** settings to the Intro Course, which implies it was previously more rigid than the rest of the app. (High)
- **After the course** ([help 78](https://help.wakingup.com/article/78-after-completing-the-introductory-course-what-should-i-do)): three suggestions only. Continue with the Daily Meditation and revisit the Daily Wisdom queue. Try the "After the Introductory Course" playlist of 28 meditations, each paired with a related lesson or clip from Theory and Life. Or explore at your own pace. There is no forced next step. (High)
- **Gating or unlocking: unresolved, with conflicting claims.**
  - A third-party product analysis ([piyushkalra](https://piyushkalra.substack.com/p/better-products-1-waking-up-by-sam)) says the Daily Meditation unlocks only after the Intro Course.
  - A lifestack review says the library "opens fully" after ten sessions.
  - Official help reads as recommendation, not lock: it says to "explore the rest of the app at your own pace".
  - Free-tier counts conflict across sources: "first 5 sessions" (a 2020 App Store review), "first five days" (ixcoach), a 7-day trial (current wakingup.com), a 14-day trial ([wakingup.com/14-day-trial](https://www.wakingup.com/14-day-trial)), a 30-day guest pass with no card ([guest pass page](https://dynamic.wakingup.com/guestpass/SC3F99A07)).
  - Best reading: the paywall is the subscription, not per-day unlocks, and offers have varied by campaign. This needs confirming on the phone. (Low)
- **Long-form challenges** (Deep Rest Reset and similar) live on a separate web hub at reset.wakingup.com and not in the mobile app ([help 366](https://help.wakingup.com/article/366-where-does-the-challenge-live-i-opened-the-app-and-cant-find-it)). (High)

## 4. Meditation timer

(Official copy is thin; most detail is from release notes.)

- Sold as the unguided tool: "Select a duration and optional interval bells" ([routine page](https://wakingup.com/inside-the-app/routine)). (High)
- **Redesigned in 3.22 (Jun 2026)** "with more functionality", plus two new bells to open and close sessions. Sessions started appearing in History in 3.21 (Apr to May 2026). (High that this happened, Low on exact controls.) Exact post-redesign controls need the phone tour.
- Daily and Practice sessions can carry a countdown timer, starting and ending bells, and background sounds (Explore page; 2.23.0 added "countdown timer and starting bell" to the Daily Meditation settings window and an option to skip that window). (High)
- Third-party reviews describe the timer as simple, with fewer options than dedicated timer apps ([healthynexercise](https://healthynexercise.com/top-meditation-apps/waking-up-meditation-app-review/), Low-Med).
- A Google Play reviewer (Aug 2026) complained that the bell fires about **3 seconds before the timer ends**. Waking Up replied only with a "please email support" boilerplate ([Play listing](https://play.google.com/store/apps/details?id=org.wakingup.android)). (Med, one review.) Bell timing semantics are a real user expectation.
- Google Health/Fit sync exists for Android sessions ([help 142](https://help.wakingup.com/article/142-am-i-able-to-connect-waking-up-to-the-google-fit-app)). (High)
- I found no mention of presets, saved timer configurations, or ambient-sound mixing beyond "background sounds". Check on the phone.

## 5. Player

- **Settings via a slider icon** in the player, shown for the Daily Meditation ([help 116](https://help.wakingup.com/article/116-how-do-i-adjust-the-length-of-my-daily-meditations)). (High)
  - **Extend session:** the first 20 extra minutes are spread through the track as added silence. Anything beyond 20 goes at the end. A "Don't show me this next time" checkbox suppresses the prompt.
  - Other Practice sessions can add time at the end only ([help 338](https://help.wakingup.com/article/338-can-i-adjust-the-length-of-meditations-in-the-app)).
  - 3.22 added "customize any meditation before it begins".
- **Autoplay with an optional Interlude** (a short buffer between tracks) was added in 3.22. Background sounds can be set **separately for Practice and for Theory/Life**.
- **Downloads** ([help 115](https://help.wakingup.com/article/115-can-i-download-content-locally-and-play-it-offline), [help 335](https://help.wakingup.com/article/335-where-can-i-find-my-saved-content)):
  - Per track from the three-dot menu in the player, or a whole series from its page.
  - Filter by "Downloaded" in My Library.
  - Account Settings has an **Automatic Download** option with a Wi-Fi-only toggle.
- **Save and playlists:** the bookmark icon saves to "My Saved Sessions". Unlimited playlists since 2.26.0, which can be shared. (High)
- **Background play** is assumed throughout. The only help article touches it as a failure case: [audio pausing on Android](https://help.wakingup.com/article/65-my-audio-pauses-unexpectedly) points at battery optimization on Samsung and other OEMs. (High)
- **Pre-play detail screen:** session summaries and teacher bios appear before you commit to listening ([screensdesign write-up](https://screensdesign.com/showcase/waking-up-meditation-wisdom), Med). Search shows "Top Searches".
- **CarPlay** for select content (3.23); Apple Watch listed in the App Store compatibility. (High)
- A dated review notes there were no singing bowls, chants or soundscapes in sessions ([iMore](https://imore.com/apps/this-is-the-best-meditation-app-ive-ever-used-and-ive-tried-them-all)). Background sounds have since been added as an opt-in, which shows the team's stance: voice-first, with ambience as a user choice. (Med)
- Duration variants: one third-party review lists daily sessions of 10/15/30/45 minutes (Low and possibly old). The current official model is "default length + extension", not a variant picker. Check on the phone.

## 6. Practice versus theory

(High, official; this is the app's core IA idea.)

- **Explore is organized by what the content is for:**
  - **Practice:** meditation, contemplation, daily exercises.
  - **Theory:** the philosophy and science behind meditation.
  - **Life:** living a more examined life (relationships, work, Stoicism and the like).
  - Source: [help 76](https://help.wakingup.com/article/76-how-is-the-app-organized).
- **Conversations and Q&As** (Sam Harris with guests) are pinned at the top of Explore as a separate lane.
- **The two are bridged on purpose:**
  - The Intro Course interleaves sessions and lessons.
  - "After the Introductory Course" pairs each of 28 meditations with a related Theory/Life item.
  - Daily Wisdom surfaces theory clips on Home.
  - Different background sounds are allowed for Practice and Theory/Life.
- **Stated rationale:** "Unlike conventional meditation apps, Waking Up blends practice with theory—so you not only learn to meditate but also understand how it transforms your mind" ([store listing](https://apps.apple.com/us/app/waking-up-meditation-wisdom/id1307736395)). The help site calls it "a whole new operating system for your mind" ([help 69](https://help.wakingup.com/article/69-what-makes-waking-up-different-from-other-meditation-apps-and-courses)).
- **Cost, per critics:** the theory-heavy tone is the most-cited reason people bounce ("for people who want to meditate without thinking about meditation, this is a significant mismatch", [lifestack](https://lifestack.ai/blog/waking-up-app-review), Low-Med; that site sells a competitor).

## 7. Visual and interaction design

- **Agency and brief** ([Partner via 100 Archive](https://www.100archive.com/projects/waking-up), 2021). (Med; it is the agency's own page and credits)
  - Partner delivered a design system and a full UI redesign.
  - Designer: Luke Kavanagh. Creative director: Stéphane Fournier.
  - Brand identity and visual identity were created separately by Franz Blach and Stephanie Blach. Partner implemented them.
  - The UI was meant to "complement and elevate" the new commissioned artwork. The client described the goal as browsing the app being like **"walking through the MOMA"**.
  - The aggressive timeline and handoff were to two outside dev teams (Z1 Digital, Clevertech) for iOS, Android and web.
  - The page gives no typography, palette, or system detail.
- **Art direction:** over 100 artists work with the company ([About](https://www.wakingup.com/about)). An illustrator, [Jason Chatfield](https://www.jasonchatfield.com/blog/tag/portraits), describes drawing conversation portraits during the redesign. They were individually styled rather than templated, and had to work in **both dark and light modes**, stay readable at small phone sizes, and hold up on desktop. (Med) So both light and dark themes exist.
- **2018 original rationale** ([Metalab](https://archive.metalab.com/projects/waking-up)). (Med; a marketing case study)
  - "Distraction-free": daily guided meditations and lessons without clutter.
  - A self-timer for experienced users alongside guided sessions for beginners.
  - Portable use, from short workday breaks to remote settings.
  - A merged onboarding.
  - It claims no research or metrics.
- **Observed character from reviewers** (Med):
  - Dark, minimal, abstract art, calm ([screensdesign](https://screensdesign.com/showcase/waking-up-meditation-wisdom)).
  - Audio-first, so the interface stays quiet.
  - "Clean, uncluttered… keeps your focus on practicing, not scrolling" ([healthynexercise](https://healthynexercise.com/top-meditation-apps/waking-up-meditation-app-review/)).
  - "Incredibly easy to use, with simple controls" ([iMore](https://imore.com/apps/this-is-the-best-meditation-app-ive-ever-used-and-ive-tried-them-all)).
- **Copy tone:** release notes are plain and brief, with a recurring "No big changes… just refining the little details" line on maintenance releases. Notification windows are described as making the app "supportive rather than intrusive" ([More tab page](https://m.wakingup.com/inside-the-app/more)). (High)
- **Motion, typography, colour:** nothing stated publicly beyond the above. Don't cite more without the phone tour.

## 8. Retention and engagement

- **Reminders** ([More page](https://m.wakingup.com/inside-the-app/more), [help 92](https://help.wakingup.com/article/92-what-s-the-best-way-to-build-a-consistent-meditation-practice)):
  - Three opt-in streams under More, Notifications & Reminders: **Meditation Reminder, Moment, Daily Quote**.
  - Moment and Daily Quote have a user-set time window. Each can go by push, email, or both.
  - Habit advice in help: start small (about 10 minutes), set a physical trigger, do it at the same time daily. (High)
- **Stats** (High):
  - More page: sessions completed, minutes in the app, minutes meditating.
  - Account data lists total minutes, sessions, **days practiced**, audio progress and saved content ([help 327](https://help.wakingup.com/article/327-how-do-i-delete-my-account)).
  - 2.22 split Total Minutes from Practice Minutes.
  - 3.25 (Aug 2026) added Profile with practice minutes, weekly activity, and top teachers and sections.
  - Timer sessions count in History since 3.21, with a "better tracking of Practice & Total Minutes" fix.
- **Streaks:**
  - I found **no official streak counter**. Official pages mention neither streaks, badges nor "mindful days".
  - "Mindful Days" is a [Ten Percent Happier](https://support.tenpercent.com/article/114-mindful-days-statistics-in-your-app-profile) feature and not Waking Up's. I checked because the brief named it.
  - A 2020 blogger said the app "tracks days of use" and credited it for building a habit ([frimmin](https://www.frimmin.com/2020/08/)). One SEO review claims "a subtle meditation streak". Both are weak. Confirm on the phone. (Low)
- **Gamification stance:** no stated policy, but the observed system is quiet: opt-in reminders, activity totals, no badges or leaderboards in the official copy. A reviewer describes the habit support as "flexible… rather than streak pressure" ([piyushkalra](https://piyushkalra.substack.com/p/better-products-1-waking-up-by-sam), Low). The brand copy leans on non-dogmatic, "move forward at your own pace" language. (Med, inferred)
- **Social and growth:**
  - **Guest pass:** a link gives a friend 30 free days, no credit card, via email entry and a code ([example page](https://dynamic.wakingup.com/guestpass/SC3F99A07)). A "Share Waking Up" screen is shown in the [screensdesign walkthrough](https://screensdesign.com/showcase/waking-up-meditation-wisdom). Allowances for members are not published. (Med)
  - **Promo/gift codes:** redeemed at app.wakingup.com ([help 111](https://help.wakingup.com/article/111-i-have-a-promo-gift-code-how-do-i-redeem-it)).
  - **Scholarship:** free access for anyone who cannot pay, by emailing support. Mentioned in both store listings and the onboarding. Reviews call the form manual and poorly advertised ([healthynexercise](https://healthynexercise.com/top-meditation-apps/waking-up-meditation-app-review/)).
  - **Community:** a separate platform with email one-time-code login, live Q&As and local meetups. It is not in the app ([Community page](https://www.wakingup.com/community)). Reviewers call it "bolted on" (Low).

## 9. Distinctive features

- **Moment** (short mindful-in-daily-life audio, push-delivered), **Daily Wisdom** (queue of clips from across the library, filterable, skippable by swipe), **Daily Quote** (text push and widgets). Together they form a layer that reaches users outside sit-down time.
- **Alan Watts and archival talks** preserved and searchable. Conversations get commissioned portraits.
- **Daily Meditation with an extend dial** that spreads silence through the track, an unusual mechanic that lets one recording serve many lengths.
- **Per-section background sounds** (Practice vs Theory/Life), with smooth fading since 3.19.
- **Playlists:** user-made, shareable, and team-curated.
- **CarPlay, widgets and Google Health sync.**
- **Free-for-those-who-can't-pay** as a visible product value. A guest pass with no credit card.
- **Sleep:** Sleep Talks and Guided Sleep Meditations, added only in Oct 2025. A 2026 reviewer still calls sleep content "the most significant gap" ([lifestack](https://lifestack.ai/blog/waking-up-app-review), Low-Med).

## 10. Complaints (what not to copy)

Reddit was unreachable, so these come from the Play listing, App Store, and reviews.

- **Ratings:** [App Store](https://apps.apple.com/us/app/waking-up-meditation-wisdom/id1307736395) 4.9 with about 42.7K ratings; [Play](https://play.google.com/store/apps/details?id=org.wakingup.android) 4.6 with about 41.1K. The Android score runs lower. Apple's curated review slice is overwhelmingly positive and says little about friction. (High)
- **Price and billing** are the dominant complaint.
  - A July 2026 Play review: a monthly signup threatened a $150 annual charge, and support's fix led to a $20/month re-signup versus $13 a few days earlier. 11 people marked it helpful.
  - The App Store lists multiple price tiers ($19.99 monthly, $149.99 yearly, $229.99 family).
  - Another aggregator reports the trial ending around day 7 of the Intro Course, and demands for a month-to-month option ([healthynexercise](https://healthynexercise.com/top-meditation-apps/waking-up-meditation-app-review/), Low, SEO page).
  - Lesson: keep money out of the practice flow.
- **Difficulty ramp for beginners:** academic language and abstract instructions, noted by an Apple reviewer (2023) asking for a gentler Practice section, and by the ixcoach review (Day 14 critique). (Med)
- **Navigation and organization:**
  - The library is called harder to navigate than it should be.
  - Saving and organizing favorites are described as less intuitive than competitors (Low).
  - The official fix path was a series of redesigns: My Library promoted to the tab bar, playlists, and search filters.
- **Bugs, on Android especially:** audio pausing on battery-optimized devices (official help acknowledges it), Google sign-in problems, resume position lost on long talks (the last two Low).
- **Timer details:** bell timing (above); fewer options than dedicated timer apps.
- **Fit:** "heavy" tone for people who only want to decompress; thin sleep content until late 2025; open-awareness style hard for some ADHD users (Low-Med, from a competitor's blog).
- **Support replies** to public reviews are boilerplate. (Med)

## 11. Platform differences (iOS vs Android)

- **iOS only:** CarPlay, Apple Watch and visionOS listing, Apple Family Sharing for the family plan.
- **Android:** Google Health/Fit connection ([help 142](https://help.wakingup.com/article/142-am-i-able-to-connect-waking-up-to-the-google-fit-app)); a dedicated help article on playback pausing due to OEM battery optimization ([help 65](https://help.wakingup.com/article/65-my-audio-pauses-unexpectedly)).
- Billing and subscription management differ by store. Some plans are only buyable on the web (monthly is bought on wakingup.com per [help 108](https://help.wakingup.com/article/108-does-waking-up-offer-monthly-subscriptions)).
- Feature releases appear to be lockstep since the version numbers converged (my inference from the identical 3.27 text on both stores).

## Patterns worth borrowing

1. **Four tabs, stable for years.** Put growth into customizable Home modules, not new top-level destinations.
2. **Home as a user-chosen shelf with a Customize switch.** Daily item, Continue Listening, a few pinned series, and optional modules. It is calm because the user decides what appears.
3. **Cap pinned focus at three.** My List is a small, deliberate constraint. It beats an infinite "recommended for you".
4. **Name the lanes by purpose**, not by format (Practice / Theory / Life). It makes the library legible and teaches the product's philosophy.
5. **Bridge the lanes.** Pair a practice with a related lesson. Surface short clips on Home as a low-commitment doorway.
6. **One recording, many lengths.** Extension adds silence (spread through the track up to 20 minutes). Remember the choice, with a "don't ask again" checkbox and a player slider to change it later.
7. **Separate background sounds for each content type**, with smooth fade in and out, and an Interlude gap between autoplayed tracks.
8. **Reminders as opt-in, windowed, channel-chosen** (push, email, or both). Frame them as supportive.
9. **Stats that are quiet totals**: minutes, sessions, days practiced, this week's activity, top teachers. No badges. Timer sittings count the same as guided ones.
10. **"Continue" and "next track" everywhere**: Continue Listening on Home, the Intro Course widget, mark played/unplayed.
11. **Offline carousel that appears on Home only when offline.**
12. **Honest, short release notes.** Say "no big changes" when that is true.
13. **Commission art as product.** Distinct portraits for conversations that survive dark and light themes (the Partner "walking through the MOMA" brief).

## Patterns worth avoiding

1. **Pushing the paywall into the middle of a 28-day course.** It is the most-repeated frustration, and billing surprises generate the harshest reviews.
2. **Fixed-order courses that assume a beginner but speak in abstractions.** Pace the vocabulary, or offer a skip.
3. **Burying the library.** Waking Up needed three rounds (Explore, My Library tab, filters) to fix findability. Plan search, filters and a library tab from the start.
4. **Timer details that surprise.** An ending bell that rings before the end is read as a bug.
5. **Splitting the product across places.** Community and challenges live outside the app (a separate login or web hub). Reviewers call it bolted on.
6. **A free tier defined by campaign.** Sources disagree on whether it is 5 sessions, 5 days, 7, 14 or 30 days. Pick one rule and state it.
7. **Opaque access routes.** Scholarship by email form, and guest-pass quotas that are not published. Meditejo, as a personal app, doesn't need any of this.
8. **Platform-specific audio fragility** (OEM battery killers). Test background playback on Samsung and Xiaomi-class devices early. Ship a one-page explanation of the battery setting.
9. **Renaming features mid-life** (Reflections to Daily Wisdom). Users track names. Choose and keep them.

## Open questions for the phone tour

- The actual Home layout, Customize panel, and the Timer's setup screen post-3.22 (presets? interval bells? two new bells' names?).
- Whether any streak or "days practiced" figure appears on the Profile, and what its tone is.
- Whether the Intro Course locks days, and what the free/trial state looks like when unsubscribed.
- Motion, haptics, typography, colour, and what the dark and light modes look like.
- Where the Share/Guest Pass screen lives, and what members see.

## Source index

- Official: [How is the app organized?](https://help.wakingup.com/article/76-how-is-the-app-organized), [A New Way to Explore](https://wakingup.com/features/explore), [Routine](https://wakingup.com/inside-the-app/routine), [More tab](https://m.wakingup.com/inside-the-app/more), [About](https://www.wakingup.com/about), [help center](https://help.wakingup.com), [14-day trial](https://www.wakingup.com/14-day-trial), [Community](https://www.wakingup.com/community).
- Stores: [App Store](https://apps.apple.com/us/app/waking-up-meditation-wisdom/id1307736395) (full 3.13.1 to 3.27 notes), [Google Play](https://play.google.com/store/apps/details?id=org.wakingup.android), APKMirror release notes ([2.17](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-17-0-release/), [2.18](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-18-0-release/), [2.22](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-22-0-release/), [2.24.1](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-24-1-release/), [2.26.0](https://www.apkmirror.com/apk/waking-up-llc/waking-up-beyond-meditation/waking-up-beyond-meditation-2-26-0-release/)).
- Design: [Partner via 100 Archive](https://www.100archive.com/projects/waking-up), [Metalab](https://archive.metalab.com/projects/waking-up), [Jason Chatfield](https://www.jasonchatfield.com/blog/tag/portraits), [screensdesign](https://screensdesign.com/showcase/waking-up-meditation-wisdom), Mobbin entries linked above.
- Reviews and analysis: [iMore](https://imore.com/apps/this-is-the-best-meditation-app-ive-ever-used-and-ive-tried-them-all), [piyushkalra](https://piyushkalra.substack.com/p/better-products-1-waking-up-by-sam), [frimmin](https://www.frimmin.com/2020/08/), [ixcoach](https://www.ixcoach.com/learn/waking-up-app-review-2026), [lifestack](https://lifestack.ai/blog/waking-up-app-review), [healthynexercise](https://healthynexercise.com/top-meditation-apps/waking-up-meditation-app-review/), [makeheadway](https://makeheadway.com/blog/waking-up-app-review/). The last four are SEO or competitor-owned pages, so weigh them lightly.
