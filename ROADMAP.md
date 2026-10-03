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

Built (README **Ads and the shop**, DESIGNDOC **Ads and the shop**). Not yet
checked on a real phone against a live AdMob account.

- [x] **Ad SDK integration** in the Android build — `android/love-ads`
      (Mobile Ads SDK + UMP consent), added by `android/ads.sh`; Google's test
      unit unless the `ADMOB_APP_ID` / `ADMOB_REWARDED_ID` repo variables are
      set. iOS waits on the iOS build.
- [x] **Revive by ad** — `src/chance.lua`, then the retake card's own getting up
      (`Game:openRetake(true)`). Once per run, asked after any bought retake.
- [x] **Double the reward by ad** — the `X2` box on both end cards
      (`src/double.lua`, `Game:doubleRun`). Once per run.
- [x] **No other ad placements.**
- [x] Every ad-facing string goes through `I18n.t` with its `ES` line.
- [ ] **Go live:** create the AdMob app and rewarded unit, set the two repo
      variables, and test the consent form from an EEA account.

### In-app purchases (non-consumable)

Built on love-iap (`src/iap.lua`, and its action in the workflow). Not yet
checked against Play: that needs the app and its products in Play Console.

- [x] **Unlock a lesson** — `lesson_<key>` for every lesson after SCIENCE,
      opening it through `Collection.lessonOpen`; the ladder still earns it free.
- [x] **Unlock everything** — `everything`: every lesson, and the two ad offers
      become free (still once per run).
- [x] **Store layer** — Google Play Billing through love-iap: restore, sync at
      launch (a refund takes a page back), entitlements in `iap.txt` beside
      `records.txt`. StoreKit is in love-iap too, for when there is an iOS build.
- [x] **A purchase page in the book** — the canteen's `LESSONS`, `MORE LESSONS`
      and `WHOLE BOOK` sections; prices read from the store.
- [x] **Dev switch respected** — `Store.opens` sits inside `Dev.opened`; with the
      dev row showing, love-iap's mock and a stand-in ad answer on a desktop.
- [x] Update `README.md` / `DESIGNDOC.md`.
- [ ] **Go live:** create the app with the same application id in Play Console,
      upload the signed `.aab` (the workflow's "Play bundle" artifact) to a
      testing track, create and activate the seven
      products (`lesson_pe`, `lesson_language`, `lesson_finance`, `lesson_music`,
      `lesson_maths`, `lesson_art`, `everything`), add license testers, and
      decide the prices — `everything` below the six lessons together.

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
