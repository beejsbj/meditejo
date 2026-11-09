# Flutter setup recipe (meditejo)

## PATH
Flutter is not on PATH by default. Each new shell needs:

    export PATH=/opt/flutter/bin:$PATH

Flutter 3.47.2 (stable) is preinstalled at /opt/flutter. The SDK download was skipped
because /opt/flutter/bin/flutter already reported 3.47.2.

## One-time setup
    git config --global --add safe.directory '*'
    flutter config --no-analytics
    flutter --version            # warm-up, ~0.2s once warm

Running flutter/dart as root prints a "Woah! You appear to be trying to run flutter as root"
banner. It is harmless noise, not an error.

## Repo setup (/home/user/meditejo, branch develop)
    git fetch origin develop
    git checkout develop
    git pull origin develop
    flutter pub get                       # ~15s (warm pub cache)

## Codegen
    # pigeon (~4s total for both inputs)
    for f in pigeon_conf.dart pigeons/*.dart; do dart run pigeon --input "$f" --package_name=medito; done
    # build_runner (~13s wall)
    dart run build_runner build --delete-conflicting-outputs

Both were run on a clean develop checkout. git status stayed clean afterwards, so the
generated files are gitignored or identical to the tracked ones.

## Screenshot tests
Harness: test/screenshots/*.dart. Every test is gated by MEDITEJO_SCREENSHOTS=1 (the
`_enabled` flag). Without it the tests are skipped. Output goes to MEDITEJO_SHOT_DIR.

Example (verified, ~27s wall, PNGs written):

    MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test test/screenshots/design_screenshots_test.dart --plain-name "Home, light"

Outputs in the baseline run: home-full-light.png, home-light.png.
--plain-name is a substring match. Names that contain ${brightness.name} expand to
"light" or "dark".

### Test names (expanded)

**test/screenshots/design_screenshots_test.dart**
- Home, light / Home, dark
- five tabs, light / dark
- You and Settings, light / dark
- Stats, 7 days, light / dark
- Stats, 30 days, light / dark
- sounds, light / dark
- sounds-mix, light / dark
- sounds-empty, light / dark
- sounds-wide, light / dark
- Library with courses and playlists, light / dark
- Add to playlist sheet, light / dark
- Customize before a session, light / dark
- Customize bell picker, light / dark
- Customize during a session, light / dark
- Customize wheel in use, light / dark
- Timer setup with its duration open, light / dark
- Library mix, light / dark
- Library mix grid, light / dark
- Explore browse, light / dark
- Explore search, light / dark
- timer (inherits the theme), light / dark
- library-empty (inherits the theme), light / dark
- the mark, frame by frame (no brightness suffix; one test)

**test/screenshots/identity_screenshots_test.dart**
- Home, <palette>, <brightness>. Palette comes from env MEDITEJO_SHOT_PALETTES
  (default `tide,dusk,forest`). Names: Tidewater (tide), Dusk (dusk), Forest (forest).
  All ids: clay, dusk, forest, sumi, riso (Lotus Riso), lagoon, saffron, tide, ember.
- Settings › Appearance, light / dark
- a week of daily marks, light / dark
- the launcher icon on a home screen, light / dark

**test/screenshots/art_player_screenshots_test.dart**
- the player over its art, light / dark

Total across the 3 files. Expanded counts: design 44 plus the mark
test (45); identity 12 at the default palettes (6 Home + 6 others); art player 2.

## Gotchas
- Flutter is not on PATH. Export it in every shell (see PATH above).
- Screenshot tests do nothing without MEDITEJO_SCREENSHOTS=1. The run exits 0 with the
  test shown as skipped.
- --plain-name needs the expanded name, e.g. "Home, light". The raw template
  "Home, ${brightness.name}" does not match.
- MEDITEJO_SHOT_DIR must exist before the run. Create it first with mkdir -p.
- The identity palette tests read MEDITEJO_SHOT_PALETTES. Unset, they use tide,dusk,forest.
- Codegen must run after pub get and before the tests. Without it, the generated
  .g.dart and drift files are missing and the app will not compile.
- Git worktrees have their own working tree. Each worktree needs its own
  `flutter pub get` (~15s here) and codegen (pigeon ~4s, build_runner ~13s). The pub
  cache is shared, so pub get is quick. A worktree was not created or timed in this run,
  so these figures come from the main checkout.
- Do not commit generated outputs. After codegen, the working tree is clean here, but
  check `git status` before any commit.
