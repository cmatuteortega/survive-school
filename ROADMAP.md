# ROADMAP.md

What stands between the game as it is and a polished commercial mobile release
— the Vampire Survivors / Brotato tier rather than a literal AAA budget. The
systems depth (seven lessons with a boss and an encore each, four courses,
twelve weapons, forty-five fusions, the book's library, canteen, homework,
collection and tally) is already there;
what is listed here is breadth, feel, onboarding and the platform around it.

Tick a box when the item ships, and update `README.md` / `DESIGNDOC.md` as the
behaviour lands — this file tracks the work, it does not replace the argument
for it.

## 1. Art

- [x] **Character sprites** — finished art for SHOOTMAN, SWORDSMAN, STARMAN,
      SKATEMAN (`src/characters.lua`, `src/sprites.lua`).
- [x] **Secondary animation** — idle bobs, squash and stretch on hits, a death
      animation per enemy type, and wind-up frames before boss attacks.
- [x] **Per-lesson pages** — each subject plays on its own page, baked from
      `art/<subject>/` (`lua art/bake.lua`) and tiled by `src/background.lua`.

## 2. Bosses and enemies

- [x] **Boss variations** — a distinct boss per lesson and a second one, its
      encore, sent by the courses with `bosses = 2` (`src/subjects.lua`): the
      eye and the atom, the whistle and the deodorant, the dictionary and the
      red pen, the stamp and the piggy bank, the metronome and the speaker, the
      die and the tesseract, the still life and the marble. Each has its own
      patterns and telegraphs (`BOSSES.md`, `3dmethod.md`).
- [ ] **Larger enemy roster** — 10 types now (blob, bat, skull, wad, blot,
      drop, bulb, grin, eye, red eye). Add ranged attackers, chargers, splitters, shielded
      and support enemies, each one asking for a new reaction the way the wad,
      blot, bulb and grin each do (README **What walks on**).
- [ ] **Stage hazards / gimmicks** — obstacles, layouts or a rule unique to each
      subject, so lessons differ in *where* you fight as well as *what* comes.
  - [ ] **Worksheets** — puzzles printed on the page that pay for being solved
        under pressure (`src/worksheet.lua`, `WORKSHEETS.md`, README
        **Worksheets on the page**). Tic-tac-toe on every page and MATHS's pop
        quiz and sequence are built; one puzzle per lesson is the rest of it.

## 3. Audio

- [ ] **Music per lesson** — one looping track today (`src/music/ost.mp3`).
- [ ] **Boss theme**, **menu theme**, and short **win / lose stings**.
- [ ] **Scissors snip** — the scissors borrow a pitched-up brush swish because
      no snip is recorded yet (README **Sound**).
- [ ] **Missing foley** — enemy deaths, boss arrival and attacks, pickups, gems,
      evolutions.

## 4. Game feel

- [x] **Haptics** — one short pulse on taking a hit, sized like the page's knock
      (`src/haptics.lua`, `Player:hurt`), and a `VIBRATION` row in settings to
      turn it off. Deliberately the only buzz for now (README **Settings**);
      boss slams, level-ups and evolutions can be weighed against that later.
- [x] **Juice pass** — review hit-stop, flashes and particles against the
      genre's best now that the base systems are stable.

## 5. Onboarding and UX

- [x] **Tutorial / guided first run** — the draw-to-answer input model
      (README **Asking by drawing**) is unusual and should be taught, not
      discovered. A hand drawing a dashed line (`src/coach.lua`, README
      **Being shown how**): a diagonal through the YES box after a few idle
      seconds on the title, and a scribble across a monster in a run's opening
      seconds until the first kill made while drawing.
- [x] **Story framing** — a short intro (first day of school): the first launch
      opens on eight scenes seen through a blinking eye, and the eye opens on
      the title at the end (`src/intro.lua`, README **The opening**).
- [ ] **Ending cards** — an ending card per course (`src/course.lua`), split out
      of story framing when the intro shipped.
- [x] **Accessibility**
  - [x] Colourblind / high-contrast palette option (a swapped eight-colour set,
        so the overprint rule still holds).
  - [x] Reduced motion / reduced screen shake toggle.
  - [x] Text size option.
- [ ] **More languages**
  - [x] EN, ES (`src/i18n.lua`), and DE, FR, IT, PT-BR (`src/lang/`), behind
        the settings page's LANG row (`I18n.langs`).
  - [ ] JA, KO, ZH, RU — need glyphs past the 3x5 Latin face (`src/font.lua`).

## 6. Platform

- [ ] **iOS build** — only `.github/workflows/android.yml` exists.
- [ ] **Cloud save** — saves are flat text files in the LÖVE save directory.
- [ ] **Achievements** — Google Play Games / Game Center; the tally and homework
      list (`src/tally.lua`, `src/challenges.lua`) map straight onto them.
- [ ] **Leaderboards** — per lesson and per course.
- [x] **Run resume on app kill** — the bookmark is written every five seconds
      of play (`Game:keepBookmark`) and on losing focus, since Android never
      calls `love.quit` on a backgrounded app it kills and blocks the game
      before the background event can be read. A kill or crash costs at most
      five seconds. Not yet checked on a real phone.
- [x] **Save versioning** — every save file goes through `src/save.lua`: a
      `save N` stamp, `Save.migrate` steps run on load from the file's version
      up (an unstamped file from an earlier APK is version 0 and read as is),
      and a copy written first so a kill mid-save never leaves a file cut off.
      A downgrade (an older APK over a newer one) reads stamped files wrong.
- [ ] **Gamepad / keyboard play** — `src/input.lua` is touch and mouse only;
      worth it for desktop and Chromebook, optional for a mobile-only release.
- [ ] **Device coverage** — check the fit (`main.lua`, safe insets) on real
      notched phones, foldables and tablets, in both orientations.
- [ ] **Crash reporting** and **analytics** (opt-in).

## 7. Retention and business model

**Decided: free to start (SCIENCE), opt-in rewarded ads, and IAP that only
unlocks content: the full game, then the whole book.** The book's economy is earned (the purse, the canteen that gives
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
- [x] Every ad-facing string goes through `I18n.t`, with its `ES` line and a
      line in each of `src/lang/{de,fr,it,pt}.lua`.
- [ ] **Go live:** create the AdMob app and rewarded unit, set the two repo
      variables, and test the consent form from an EEA account.

### In-app purchases (non-consumable)

Built on love-iap (`src/iap.lua`, and its action in the workflow). Not yet
checked against Play: that needs the app and its products in Play Console.

- [x] **Full game** — `full_game`: every lesson after SCIENCE and every gated
      line of the library. Without it the book is SCIENCE and the ungated lines,
      and every shut page and shelf says `PURCHASE FULL GAME TO TRY`.
- [x] **Whole book** — `everything`, sold only once `full_game` is owned: every
      lesson and library line opened outright and the two ad offers free (still
      once a run). The homework still counts only what was earned
      (`Collection.earned`).
- [x] **Store layer** — Google Play Billing through love-iap: restore, sync at
      launch (a refund takes the book back), entitlements in `iap.txt` beside
      `records.txt`. StoreKit is in love-iap too, for when there is an iOS build.
- [x] **Where it is sold** — the canteen's `SHOP` section (the full game, then
      the whole book, with `RESTORE` and `AD PRIVACY`), and a padlock on the
      title and the timetable that opens the full game's card
      (`src/fullgame.lua`). Prices read from the store.
- [x] **Dev switch respected** — both gates sit inside `Dev.opened`; with the
      dev row showing, love-iap's mock and a stand-in ad answer on a desktop.
- [x] Update `README.md` / `DESIGNDOC.md`.
- [ ] **Go live:** create the app with the same application id in Play Console,
      upload the signed `.aab` (the workflow's "Play bundle" artifact) to a
      testing track, create and activate the two products (`full_game` at
      3,99 EUR, `everything` at 1,99 EUR), and add license testers.

### Store listing and compliance

- [ ] **Privacy policy** — hosted at a public URL and linked from the listing;
      required by Play once AdMob and billing are in.
- [ ] **Data safety form** — what AdMob, UMP and love-iap collect and share.
- [ ] **Content rating** (IARC questionnaire) and **target audience** — with
      ads in the game, an audience that includes children brings in the
      Families policy.
- [ ] **Store listing** — icon, feature graphic, screenshots and short / full
      descriptions, in EN, ES, DE, FR, IT and PT-BR.

## 8. Production quality

- [ ] **Automated checks** — beyond `luac -p`: a headless simulated run per
      course to catch broken fusions, crashes and difficulty spikes.
- [ ] **Balance pass** — the fourteen bosses and four courses tuned against
      each other by hand, now that every lesson sends two bosses at the courses
      that ask for them.
- [ ] **Low-end device profiling** — late-game hordes and projectile-heavy
      builds on a cheap Android phone.
- [ ] **Docs cleanup** — README **Not built yet** still opens with "No audio.",
      which the **Sound** section contradicts.
- [ ] **Soft launch** — a closed testing track in Play Console with outside
      players, and a round of fixes from their feedback before the public
      release.
