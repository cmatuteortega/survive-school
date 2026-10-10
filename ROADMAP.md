# ROADMAP.md

What stands between the game as it is and a polished commercial release on
phones (Google Play, then the App Store) and on Steam (Windows, macOS, Linux and
the Steam Deck) — the Vampire Survivors / Brotato tier rather than a literal AAA
budget. The
systems depth (seven lessons with a boss and an encore each, four courses,
twelve weapons, forty-five fusions, the book's library, canteen, homework,
collection and tally) is already there;
what is listed here is breadth, feel, onboarding and the two storefronts around
it. The two releases sell differently: free to start with IAP on a phone, sold
whole on a computer (`Store.sold` is false off Android/iOS, so Steam needs no
shop at all).

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
- [x] **Larger enemy roster** — 10 types now (blob, bat, skull, wad, blot,
      drop, bulb, grin, eye, red eye). Add ranged attackers, chargers, splitters, shielded
      and support enemies, each one asking for a new reaction the way the wad,
      blot, bulb and grin each do (README **What walks on**).
- [x] **Stage hazards / gimmicks** — obstacles, layouts or a rule unique to each
      subject, so lessons differ in *where* you fight as well as *what* comes.
  - [x] **Worksheets** — puzzles printed on the page that pay for being solved
        under pressure (`src/worksheet.lua`, `WORKSHEETS.md`, README
        **Worksheets on the page**). Tic-tac-toe on every page, and every lesson
        has its own: the pop quiz and the sequence (MATHS), the lab board and the
        circuit (SCIENCE), Simon and the stave (MUSIC), the dodgeball pit and
        hopscotch (P.E.), join the dots and the portrait (ART), the till and the
        market (FINANCE), and hangman (GRAMMAR).

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

Shared by both releases first, then what each storefront needs of its own.

### Both

- [x] **Run resume on app kill** — the bookmark is written every five seconds
      of play (`Game:keepBookmark`) and on losing focus, since Android never
      calls `love.quit` on a backgrounded app it kills and blocks the game
      before the background event can be read. A kill or crash costs at most
      five seconds.
- [x] **Save versioning** — every save file goes through `src/save.lua`: a
      `save N` stamp, `Save.migrate` steps run on load from the file's version
      up (an unstamped file from an earlier APK is version 0 and read as is),
      and a copy written first so a kill mid-save never leaves a file cut off.
      A downgrade (an older APK over a newer one) reads stamped files wrong.
- [x] **Device coverage** — the fit (`main.lua`, safe insets) checked on real
      notched phones, foldables and tablets, in both orientations.
- [ ] **Achievements layer** — one module the tally and homework list
      (`src/tally.lua`, `src/challenges.lua`) report to, with a backend per
      store (Play Games, Game Center, Steam) and none on a bare build, the way
      `src/store.lua` sits over `src/iap.lua`. One table of ids, one row per
      homework entry, so a new entry is one row on every store.
- [ ] **Leaderboards layer** — per lesson and per course, behind the same kind
      of seam; which score a board ranks (time, kills, the purse) decided once
      for every store.
- [ ] **Cloud save** — every save already goes through `src/save.lua`, so this
      is a sync at that one door. Conflicts (two devices, both played) need a
      rule: the newer `records.txt` / `tally.txt` wins, or the two are merged
      line by line, since both only ever grow.
- [ ] **Crash reporting** and **analytics** (opt-in) — `love.errorhandler`
      writing the trace to the save directory at least, so a player can send it;
      anything that leaves the device goes in the privacy policy and the data
      safety form.

### Mobile

- [ ] **iOS build** — only `.github/workflows/android.yml` exists. love-ios,
      the same `main.lua conf.lua src`, StoreKit through love-iap (already in
      it) and AdMob + UMP for iOS beside `android/love-ads`.
- [ ] **Play Games Services** — sign-in, achievements and leaderboards on
      Android, the backends for the layers above.
- [ ] **Game Center** — achievements and leaderboards on iOS.
- [ ] **Cloud save on a phone** — Play Games Saved Games on Android, iCloud
      key-value / CloudKit on iOS.

### Steam

The desktop builds (`.github/workflows/desktop.yml`) are the starting point: the
game is already sold whole there, opens fullscreen, plays with a mouse and
pauses on `Esc`.

- [ ] **Steamworks partner account** — the app credit (US$100 per app),
      the tax interview and bank details, and an app id.
- [ ] **Steamworks SDK in LÖVE** — a LuaJIT binding such as luasteam (its
      `.dll` / `.dylib` / `.so` beside the fused executable, and `steam_api64`
      / `libsteam_api` from the SDK), loaded with `pcall` so a build launched
      without Steam, or the itch.io / bare `game.love` one, still runs. A
      `steam_appid.txt` for local testing only, never shipped.
- [ ] **Steam achievements** — the Steam backend of the achievements layer,
      the same ids set up in the Steamworks admin, with their icons (64x64,
      locked and unlocked, drawn in the palette).
- [ ] **Steam leaderboards** — the Steam backend of the leaderboards layer.
- [ ] **Steam Cloud** — Auto-Cloud on the fused save directory
      (`notebook-survivors/` under `%APPDATA%`, `~/Library/Application Support`
      and `~/.local/share`), every save file listed, `options.txt` left out if
      the window and screen settings should stay per machine.
- [ ] **Controller support** — `t.modules.joystick` is off in `conf.lua` and
      `src/input.lua` is touch and mouse only. The draw-to-answer model
      (README **Asking by drawing**) needs a stick-drawn pen: one stick moves,
      the other steers a cursor that draws while a trigger is held, and every
      screen (title, settings, the back pages, level-up, the end cards) walkable
      by d-pad. Steam Input's default configuration set to the gamepad, and the
      button glyphs drawn in the 3x5 face. The keyboard: rebinding, and the
      menus walkable by arrow keys too.
- [ ] **Steam Deck** — 1280x800 (16:10) needs nothing of the fit (`main.lua`):
      zoom 4, a 320x200 page. Check text size on a 7" screen, controller-only
      play from boot, no launcher, and suspend / resume through the bookmark.
      Aim for **Verified**.
- [ ] **Linux depot** — ship the fused folder (the game, `love` and its
      libraries) rather than the AppImage, which needs FUSE and fights the
      Steam Linux Runtime; set the launch option to the Steam Linux Runtime
      (sniper) container.
- [ ] **macOS depot** — the app is re-signed ad hoc today; sign it with a
      Developer ID and notarise it, so it opens without a Gatekeeper prompt.
- [ ] **SteamPipe upload in CI** — a job after the desktop builds that runs
      `steamcmd` with an app build script and one depot per OS, behind a
      `STEAM_USERNAME` / `STEAM_CONFIG_VDF` secret, pushing `v*` tags to a
      beta branch to be set live by hand.
- [ ] **Steam overlay** — check it draws over LÖVE's OpenGL window on all
      three OSes, and that opening it pauses a run the way losing focus does.
- [ ] **Rich presence** (optional) — the lesson and course being played.

## 7. Retention and business model

**Decided: on a phone, free to start (SCIENCE), opt-in rewarded ads, and IAP
that only unlocks content: the full game, then the whole book. On Steam, sold
whole at one price: no ads, no shop.** The book's economy is earned (the purse, the canteen that gives
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

### Store listing and compliance — mobile

- [ ] **Privacy policy** — hosted at a public URL and linked from the listing;
      required by Play once AdMob and billing are in, and by the App Store.
- [ ] **Data safety form** — what AdMob, UMP and love-iap collect and share.
- [ ] **Content rating** (IARC questionnaire) and **target audience** — with
      ads in the game, an audience that includes children brings in the
      Families policy.
- [ ] **Store listing** — icon, feature graphic, screenshots and short / full
      descriptions, in EN, ES, DE, FR, IT and PT-BR.
- [ ] **App Store** — the App Privacy labels, age rating, and the listing again
      in App Store Connect once there is an iOS build; App Review.

### Store listing and compliance — Steam

- [ ] **Store page** — short and long descriptions, tags, genres, supported
      languages (EN, ES, DE, FR, IT, PT-BR) and system requirements, each
      language's description and its own screenshots.
- [ ] **Store art** — header capsule (920x430), small capsule (462x174), main
      capsule (1232x706), vertical capsule (748x896), library capsule (600x900),
      library hero (3840x1240) and logo, page background; at least five
      screenshots at 1920x1080; a trailer. Pixel art blown up by whole numbers
      only, like the game.
- [ ] **Content survey** — Steam's content questionnaire (and the IARC rating
      it can generate), and the privacy policy linked if anything leaves the
      machine (crash reports, analytics).
- [ ] **Price** — a base price and Steam's regional pricing; launch discount.
- [ ] **Coming Soon** — the page live at least two weeks before release to
      gather wishlists; a demo for a Steam Next Fest. SCIENCE alone is a ready
      demo: a demo build flag that makes `Store.full()` false off a phone too,
      so the book shuts past SCIENCE the way an unbought phone's does, as its
      own app id.
- [ ] **Review** — the store page and the build each sent for Valve's review,
      a few working days each, before the release button unlocks.

## 8. Production quality

- [ ] **Automated checks** — beyond `luac -p`: a headless simulated run per
      course to catch broken fusions, crashes and difficulty spikes.
- [ ] **Balance pass** — the fourteen bosses and four courses tuned against
      each other by hand, now that every lesson sends two bosses at the courses
      that ask for them. Also on a controller, once there is one: a stick-drawn
      pen is slower than a finger and may want its own allowance.
- [x] **Low-end device profiling** — late-game hordes and projectile-heavy
      builds on a cheap Android phone.
- [x] **Docs cleanup** — README **Not built yet** no longer opens with "No
      audio.", which the **Sound** section contradicted.
- [x] **Soft launch** — a closed testing track in Play Console with outside
      players, and a round of fixes from their feedback before the public
      release.
