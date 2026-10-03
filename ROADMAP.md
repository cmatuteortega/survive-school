# ROADMAP.md

What stands between the game as it is and a polished commercial mobile release
— the Vampire Survivors / Brotato tier rather than a literal AAA budget. The
systems depth (seven lessons, four courses, twelve weapons, forty-five fusions,
the book's library, canteen, homework, collection and tally) is already there;
what is listed here is breadth, feel, onboarding and the platform around it.

Tick a box when the item ships, and update `README.md` / `DESIGNDOC.md` as the
behaviour lands — this file tracks the work, it does not replace the argument
for it.

## 1. Art

- [ ] **Character sprites** — finished art for SHOOTMAN, SWORDSMAN, STARMAN,
      SKATEMAN (`src/characters.lua`, `src/sprites.lua`), and any heroes added
      later.
- [ ] **Secondary animation** — idle bobs, squash and stretch on hits, a death
      animation per enemy type, and wind-up frames before boss attacks.
- [ ] **Per-lesson pages** — every lesson currently plays on the same page
      (`src/background.lua`); give each subject its own look.

## 2. Bosses and enemies

- [ ] **Boss variations** — today there is one boss (`bosseye`,
      `src/enemy.lua`); a distinct boss per lesson or per cycle, each with its
      own pattern and its own telegraphs.
- [ ] **Larger enemy roster** — 8 types now (skull, wad, blot, drop, bulb, grin,
      red eye, boss eye). Add ranged attackers, chargers, splitters, shielded
      and support enemies, each one asking for a new reaction the way the wad,
      blot, bulb and grin each do (README **What walks on**).
- [ ] **Stage hazards / gimmicks** — obstacles, layouts or a rule unique to each
      subject, so lessons differ in *where* you fight as well as *what* comes.

## 3. Audio

- [ ] **Music per lesson** — one looping track today (`src/music/ost.mp3`).
- [ ] **Boss theme**, **menu theme**, and short **win / lose stings**.
- [ ] **Scissors snip** — the scissors borrow a pitched-up brush swish because
      no snip is recorded yet (README **Sound**).
- [ ] **Missing foley** — enemy deaths, boss arrival and attacks, pickups, gems,
      evolutions.

## 4. Game feel

- [ ] **Haptics** — `love.system.vibrate` is used nowhere. Short pulses on taking
      a hit, boss slams, level-ups and evolutions; a settings row to turn it off.
- [ ] **Juice pass** — review hit-stop, flashes and particles against the
      genre's best now that the base systems are stable.

## 5. Onboarding and UX

- [ ] **Tutorial / guided first run** — the draw-to-answer input model
      (README **Asking by drawing**) is unusual and should be taught, not
      discovered.
- [ ] **Story framing** — a short intro (first day of school) and an ending card
      per course (`src/course.lua`).
- [ ] **Accessibility**
  - [ ] Colourblind / high-contrast palette option (a swapped eight-colour set,
        so the overprint rule still holds).
  - [ ] Reduced motion / reduced screen shake toggle.
  - [ ] Text size option.
- [ ] **More languages** — EN and ES today (`src/i18n.lua`); target FR, DE,
      PT-BR, JA, KO, ZH, RU.

## 6. Platform

- [ ] **iOS build** — only `.github/workflows/android.yml` exists.
- [ ] **Cloud save** — saves are flat text files in the LÖVE save directory.
- [ ] **Achievements** — Google Play Games / Game Center; the tally and homework
      list (`src/tally.lua`, `src/challenges.lua`) map straight onto them.
- [ ] **Leaderboards** — per lesson and per course.
- [ ] **Run resume on app kill** — confirm a run survives the OS backgrounding
      and killing the app, not only the pause flow (`src/bookmark.lua`).
- [ ] **Crash reporting** and **analytics** (opt-in).

## 7. Retention and business model

**Decided: free to play, opt-in rewarded ads, and IAP that only unlocks
content.** The book's economy is earned (the purse, the canteen that gives
everything back, the quests in `Collection.gates`), so nothing sold here buys
coins, power or skins — drawing your own hero is the feature, not something to
paywall.

### Rewarded ads (opt-in only, never forced)

- [ ] **Ad SDK integration** in the Android build (and iOS once it exists),
      with consent handling (GDPR / UMP) and a test-ad mode.
- [ ] **Revive by ad** — on death, offer one `ANOTHER CHANCE` for watching an
      ad, using the same card and behaviour as a bought retake
      (README **The retake**): half health, two seconds untouchable, the run
      carries on. Once per run.
- [ ] **Double the reward by ad** — on the end-of-run card, watch an ad to
      double what the run paid into the purse (README **The purse**). Once per
      run.
- [ ] **No other ad placements** — no interstitials or banners, least of all
      on the screens you answer by drawing.
- [ ] Every ad-facing string goes through `I18n.t` with its `ES` line.

### In-app purchases (non-consumable)

- [ ] **Unlock a lesson** — one purchase per lesson other than SCIENCE
      (P.E., GRAMMAR, FINANCE, MUSIC, MATHS, ART), each opening that lesson
      immediately instead of waiting on the timetable's ladder
      (`Collection.rungs`, `Collection.lessonOpen`). The ladder stays: every
      lesson can still be earned for free by playing.
- [ ] **Unlock everything** — one purchase that opens every lesson, removes the
      ad prompts (revive and double are then free, still once per run), and is
      priced below the sum of the single lessons.
- [ ] **Store layer** — Google Play Billing (StoreKit later), purchase
      restore, and entitlements saved beside `records.txt` so a reinstall or a
      new phone gets them back.
- [ ] **A purchase page in the book** — a section added to the canteen
      (a row in `SECTIONS` in `src/canteen.lua`, so it costs the spread nothing) rather
      than a new screen; prices read from the store, never hard-coded.
- [ ] **Dev switch respected** — `src/dev.lua`'s `UNLOCKS` keeps overriding
      entitlements, and comes out at launch as planned.
- [ ] Update `README.md` / `DESIGNDOC.md` (**The purse**, **The retake**, **The
      collection**) as each piece lands.

### Retention

- [ ] **Daily / weekly challenges** — seeded runs everyone plays the same; the
      game is already deterministic (DESIGNDOC **Determinism and allocation**).

## 8. Production quality

- [ ] **Automated checks** — beyond `luac -p`: a headless simulated run per
      course to catch broken fusions, crashes and difficulty spikes.
- [ ] **Low-end device profiling** — late-game hordes and projectile-heavy
      builds on a cheap Android phone.
- [ ] **Docs cleanup** — README **Not built yet** still opens with "No audio.",
      which the **Sound** section contradicts.
