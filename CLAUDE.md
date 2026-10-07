# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Where the documentation is

This file is the short operational brief. Two long documents sit beside it and
neither is optional reading before a behavioural change:

- **`DESIGNDOC.md`** — the architecture reference. Every subsystem in one place:
  the overprint pass, game states, subjects, courses, the purse, the library, the
  collection, the tally and the homework list, settings and language, characters,
  coordinates, tools, upgrades,
  spatial hashes, draw layering, damage numbers, determinism, and an
  **Extending** section that lists exactly which tables a new enemy / tool /
  upgrade / weapon / character / subject / course / perk / language needs a row
  in.
- **`README.md`** — the design document, and an unusually complete one. It
  explains *why* every tool, number and layout decision is what it is.

A third, `3dmethod.md`, covers the bosses drawn as solid objects and how to do
the same for another character: the P.E. whistle, the MUSIC metronome, the
FINANCE stamp, the GRAMMAR dictionary and the ART marble, built of boxes, cones,
cylinders and ellipsoids and ray-traced live by one shared tracer
(`src/solid.lua`, their models rows in `src/solids.lua`) -- turned to any
heading, the stamp rocking, diving and squashing, the dictionary's board
swinging and its leaves clapping shut, the marble carved a little on every hit,
the metronome's pendulum plotted on top through the body's own projection, and
every picture kept by heading and pose and painted in the frame it is needed
(they were baked into rings of ASCII views once, and `3dmethod.md` says why they
are not now) -- the eye, painted a pixel at a time
every frame off a turning sphere (`src/eyeball.lua`), the MATHS die, painted
the same way off flat faces (`src/dice.lua`), and the ART still life, a cube, a
sphere and a cone painted the same way and lit by a lamp that moves
(`src/plaster.lua`), and the SCIENCE atom, a cluster of nucleons painted the eye's
way with its orbits plotted round it (`src/atom.lua`), and the FINANCE piggy bank,
nine ellipsoids painted the same way and turned to face where it goes
(`src/piggy.lua`), and the MATHS tesseract, sixteen corners turned through four
dimensions every frame and drawn as lines (`src/tesseract.lua`), and the MUSIC
speaker, a cylinder ray-traced the piggy bank's way that squashes on the beat,
tips over and rolls (`src/speaker.lua`), and the GRAMMAR red pen, a click pen
longer than the screen ray-traced the speaker's way along its own length, seen
obliquely so the page stays one to one (`src/redpen.lua`), and the P.E.
deodorant, a can of body spray ray-traced the speaker's way out of three stacked
solids with AX3 across its front (`src/deodorant.lua`).

Read the relevant section of both before changing behaviour, and update them
when behaviour changes. A number that encodes a design decision (the pushpin's
10 damage sitting one short of the skull's 12hp) is argued for in `README.md` —
do not nudge it casually.

## Running

```sh
love .                  # from the project root
```

LÖVE 11.x (`t.version = "11.4"` in `conf.lua`) — so LuaJIT / Lua 5.1 semantics:
`unpack` is a global, not `table.unpack`.

No build step, no test suite, no dependency manifest. The closest thing to a
lint pass is a syntax check, worth running after any broad edit:

```sh
for f in main.lua conf.lua src/*.lua src/lang/*.lua; do luac -p "$f" || echo "FAILED $f"; done
```

Page skins are baked from `art/<subject>/*.txt` with `lua art/bake.lua`.
A distributable is the tree zipped with `main.lua` at the root:

```sh
zip -r game.love main.lua conf.lua src art
```

`au.love` in the root is a previously built archive, not a source file.

The Android APK is built by `.github/workflows/android.yml` (any push that is not
docs or `art/`, `v*` tags as Releases, or by hand), in the same shape as
auto-chest's and demomino's: it embeds `main.lua conf.lua src` in love-android
pinned to a commit on its LÖVE 12 line, raises its `targetSdk`/`compileSdk` to
the workflow's `TARGET_SDK` (36, Play's floor), applies `love-android-audio.patch` to
that engine, and bakes the launcher icon out of `Sprites.COOLS` with
`android/icon.py` (ink on white, whole-number scales only). Unlike those two it
pins no orientation: `fullUser` in the manifest, and the settings page's SCREEN
row (`src/orient.lua`) decides at run time. The artifacts are `Survive School.apk`
and, when the signing secrets are set, `Survive School.aab` for Play Console
(never built with the throwaway key: Play locks in the first upload's key).
Signing uses the `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` /
`ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` secrets when set, and a throwaway
key per run otherwise.

The same workflow adds the two monetisation bridges to love-android's
`lua-modules/`: in-app purchases through `cmatuteortega/love-iap`'s action
(pinned to the commit `src/iap.lua` was vendored from -- bump the two together),
and rewarded ads through `android/ads.sh` (`android/love-ads`: AdMob + UMP
consent). The AdMob app id and rewarded unit come from the `ADMOB_APP_ID` /
`ADMOB_REWARDED_ID` repo variables and default to Google's test ones. On a
desktop both are inert; with the dev row showing a mock store and a stand-in ad
answer instead.

`F11` / `alt+enter` toggles fullscreen, `Esc` quits. Save state lives in
`~/Library/Application Support/LOVE/notebook-survivors/`: `options.txt`,
`bookmark.txt`, `records.txt`, `tally.txt`, `course.txt`, `iap.txt` (what the
shop has sold -- `full_game`, `everything` -- kept by love-iap), and one `.txt` per drawn design (`hero-*.txt`,
`sword.txt`, `star.txt`, `rocket.txt`, `sun.txt`, `cools.txt`, `skate.txt`,
`bomb.txt`, `lightning.txt`, `bird.txt`, `shot.txt`, `boomerang.txt`) — one line per row of the
design. Delete one to be handed the starting drawing again.

## Non-negotiable rendering rules

These four run through every module. Breaking any one is visible on screen
immediately. `DESIGNDOC.md` has the long form.

**Eight colours, no alpha.** `src/palette.lua` is the whole palette. Never pass
an alpha argument to `love.graphics.setColor`, never write literal RGB. Fades
step down a colour ramp while individual stamps drop out at random (dither) —
alpha would blend paper and ink into a ninth colour and break the overprint
lookup.

**Whole pixels only, never at an angle.** Everything renders into a low-res
canvas scaled by a whole number (`main.lua`). `love.graphics.circle` and
`love.graphics.line` are never used — use `pixelart.line`, `pixelart.band`,
`pixelart.circleOutline`, `pixelart.circleFill`, or
`rectangle("fill", x, y, 1, 1)`. No call passes a rotation to
`love.graphics.draw`; a sprite that needs a heading is baked to one of eight by
`pixelart.turn` up front. That constraint is about *sprites* only — anything
plotted by `pixelart` (the laser beam) goes down at any angle at all. A *whole*
scale is fine and is not the same thing: `Sprite:draw`'s optional `s` is how a
blown-up enemy is twice the size (`src/spawner.lua`), and an integer scale at a
floored position with nearest filtering lands on exactly the same grid. The rule
is about angles.

**Art is ASCII.** Sprites are tables of equal-length strings in
`src/sprites.lua`, one character per palette key (`.` = transparent), compiled
by `pixelart.newSprite`. Off-palette art asserts at load. Round tips past ~9px
across come from `pixelart.newDisc(radius)`.

**The canvas is not 320x180.** Zoom is picked off the *short* window edge and
the canvas is made as many game pixels as it takes to cover it — 320x180 on
16:9, 400x180 on a 20:9 phone. Nothing is letterboxed or stretched; a wider
screen shows more page. Anything positioned against a screen edge reads
`Game.vw/vh` and the safe insets (`game.inset.l/t/r/b`), never a hard-coded 320
or 180.

**Anything the player reads goes through `I18n.t`.** Write it in English where
it belongs (the upgrade's row, the tool's name, the screen's own constant), add
one line keyed by that English to the `ES` table in `src/i18n.lua` and to each
of `src/lang/{de,fr,it,pt}.lua`, and make sure whatever measures it for layout
measures the translation and not the key. Keep a translation no wider than the
Spanish where a layout was sized for it, and leave acute, grave and circumflex
accents off: the 3x5 face draws only the marks that spell (Ñ, Ä Ö Ü, Ã Õ, Ç).

## Where things live

- **Entry and frame:** `main.lua` (fit, canvas, resize, safe insets),
  `conf.lua`, `src/game.lua` (the state machine and the draw order),
  `src/camera.lua`, `src/input.lua`, `src/util.lua`. `src/dev.lua` is the one
  module here that does not ship: the settings page's `UNLOCKS` row, read by
  `Collection.has`, `Collection.lessonOpen`, `Characters.owns` and the library's
  boss page (`bossMet` / `bossBeaten`) and by nothing else, so taking it out at
  launch is five calls and a file.
- **Rendering:** `src/palette.lua`, `src/overprint.lua`, `src/pixelart.lua`,
  `src/sprites.lua`, `src/font.lua`, `src/background.lua`, `src/particles.lua`,
  `src/coach.lua` (the hand that shows how: a dashed diagonal through the YES
  box and a dashed scribble over a monster in a run's first seconds, never a
  real mark).
- **Screens:** `intro` (the first launch's opening, seen through a blinking eye
  that opens on the title), `menu`, `settings`, `timetable`, `studio`, `library`, `canteen`,
  `homework` (the challenge list, read off `challenges`), `turntable` (a boss's
  fight body on its own, turned round for the library's boss section and drawn as
  its silhouette until it is beaten), `chance` (the
  revive-by-ad offer), `fullgame` (the card the padlock on the title and the
  timetable opens, selling the full game), `double` (the x2 box on the end cards), `blank` (the page with
  nothing on it, which nothing instances today), `pause`, `levelup`, `win`,
  `over`, `retake`, `hud`, `scribble` (hand-drawn boxes), `spread` (the book the
  library, the canteen and the homework page are read in: two leaves, a crease,
  and a leaf you turn with your finger), `bookmark`, `records`, `tally`,
  `options`, `i18n` (English is the key and the Spanish sits in it; German,
  French, Italian and Portuguese are one file each in `src/lang/`).
- **Run content:** `player`, `enemy`, `spawner`, `subjects`, `solid` (the tracer
  the whistle, the metronome, the stamp, the dictionary and the marble are painted
  by: a ray against boxes, hulls, cones and ellipsoids in closed form, a pixel at a
  time, pictures kept by heading and pose), `solids` (their five models, a row
  each), `course` (how hard
  the book is: the four rungs of the difficulty ladder and what each multiplies),
  `characters`, `tools`, `upgrades`, `loadout`, `perks`, `purse`, `refund`,
  `trinket` (the pickups' bodies -- heart, ink drop, diamond, coin, wall clock,
  alarm clock and gold star -- as
  small solids painted a pixel at a time, turning over their shadows, each
  heading painted once and kept; none bigger than the hero), `worksheet` (the puzzles printed on the page -- tic-tac-toe, and MATHS's pop
  quiz and sequence -- placed like the fixed pickups; `WORKSHEETS.md` is the
  idea list), `quiz` (the pop quiz's questions and the sequences by course, and
  the typesetting that sets them in the 3x5 face),
  `store` (what is sold for money, over `iap`, love-iap's vendored file), `ads`
  (the two rewarded-ad offers),
  `collection` (what the book has opened, off `records`), `challenges` (what it
  asks you to go and do, off `tally`), `design`, `eyeball` (the eye boss's body:
  a sphere painted a pixel at a time, and its hop / roll gait), `eyeboss` (its
  brain: the stare, bowl, slam and sink, how it picks between them, its entrance
  and its death), `dice` (the MATHS boss's body: a d6, d10 and d20 as lists of
  face planes, painted a pixel at a time and rolled), `diceboss` (its brain: the
  throw, the roll it lands on, and the move that number calls for), `metronome` (the MUSIC boss's brain in the same socket: a clock
  in beats, the sweep, chord and scale played on it, and its pendulum drawn live),
  `stamp` (the FINANCE boss's brain: the ledger's cells, its leaps and poses, the
  slam, run and audit, and the PAID marks it leaves), `dictionary` (the
  GRAMMAR boss's brain: the paired ruling's groups, its hops and poses, the
  clap, riffle and definition, and the words it writes on the lines), `plaster`
  (the ART boss's body: a cube, a sphere and a cone painted a pixel at a time and
  lit from wherever its lamp is), `stilllife` (its brain: the lamp, the shadows it
  throws, the shade, and the cube dropped, the sphere bowled and the cone spun),
  `atom` (SCIENCE's second boss's body: a nucleus painted a pixel at a time and the
  tilted orbits round it), `atomboss` (its brain: the sweep, the thrown electron,
  and the fission into two halves that share one bar), `piggy` (FINANCE's second
  boss's body: a pig of ellipsoids painted a pixel at a time, cracking as it is
  hurt), `piggyboss` (its brain: the charge with bait coins in its lane, the
  recall of the coins left lying, and the shatter into rings of coins -- coins
  that land are `coin` pickups and pay into the purse), `marble` (ART's second
  boss's brain: a bust carved out of its block a little on every hit, off its
  health, and the chisel's wedge of chips, the slab that falls and breaks, and
  the rubble thrown round you), `tesseract` (MATHS's
  second boss's body: a hypercube turned in four dimensions, projected and drawn
  as lines), `tesseractboss` (its brain: the inside-out squares, the corners
  thrown, the numbered net of cubes going off in sequence, and the fold out of
  the page and back in on you), `speaker` (MUSIC's second boss's body: a
  cylindrical bluetooth speaker painted a pixel at a time -- its knit, its +/-
  buttons, its ring of lights and its pumping radiator -- in a frame that can tip
  over and roll), `speakerboss` (its brain: a beat it bounces on, the drop's rings
  with a quiet gap to dance round it in, the roll, the shuffle's notes bouncing
  round the box, and pairing with the crowd so the escort goes off), `redpen`
  (GRAMMAR's second boss's body: a red click pen far longer than the screen,
  painted a pixel at a time along its own length -- tip, ribbed grip, glossy barrel
  with its clip and print, a button that clicks), `redpenboss` (its brain: red ink
  that hurts while wet, the cursive scrawl, the WRONG ring shut on you, the whole
  pen falling flat across the box, the shake and its blots, the F written over you,
  and the stand-ins that let the barrel be hit), `deodorant` (P.E.'s second
  boss's body: a black can of body spray painted a pixel at a time -- can,
  shoulder and button, AX3 on a panel between red bands, a nozzle that goes red
  -- turned to point at you and swelling when glued), `deodorantboss` (its brain:
  the cloud -- a grid of how thick the air is that spreads, thins, is parted by
  you, cleared by kills and carried by the draught, slowing you thin and hurting
  thick -- and the spritz, the full body spray, the draught that shoves you, shake
  well, the leak, and the clog glue builds up), `wreck` (how every boss but the
  eye comes apart once it is killed: kept, shaken, flickered, burst in its row's
  colours, and the brain's `sweep` of whatever it stood on the page for itself). A
  lesson's second boss is
  its `encore` in `subjects`; only the courses with `bosses = 2` (MASTERS, PHD)
  send it -- ten minutes after the first goes down -- and only it opens the win
  card.
- **Weapons and tools:** `shot`, `sword`, `star`/`orbital`, `flock`, `rocket`,
  `sun`, `cools`, `bomb`, `skate`, `spiral`, `coffee`, `boomerang`, `storm`, `beam`, `scissors`,
  `ruler`, `compass`, `pin`, `staple`, `puddle`, `arena`.
- **World bookkeeping:** `save` (the one door every save file goes through: a
  version stamp, `Save.migrate` on load, and no half-written file), `stroke`, `mark`, `walls`, `bullet`, `gem`, `pickup`,
  `puddle` and `spike` (the eye's wet and the P.E. whistle's jacks), `damage`, `sfx` (+ `src/sfx/`, `src/music/`), `haptics` (the one buzz: being
  hit, behind the settings page's `VIBRATION` row).

`Game:buildGrid` is a 12px hash rebuilt every frame (enemy separation, bullet
hits); `src/walls.lua` is a 16px hash of pen-line segments rebuilt only when
dirty. Hit small things at a point through `Game:eachNear`; anything covering
more ground than nine 12px cells asks `Game:eachWithin`, on a tick rather than
every frame.

## Style

Comments here explain *why* a thing is the way it is — the trade-off, the bug it
prevents, the feel it produces — rather than restating the code, and modules
open with a paragraph framing what they are. Match that when editing; a change
that invalidates one of those paragraphs should update it.

Prefer adding a row to an existing table over adding a branch: nearly every
system in this game is driven off a list (`Tools.list`, `Upgrades.list`,
`Characters.list`, `Subjects.list`, `Course.list`, `Perks.list`,
`Collection.gates`, `Challenges.sections`, `Design.by`, `I18n.langs`), measured off that list, and costs
its screens nothing when it grows -- a section added to any of the three back
pages grows its book's page count by being in the list and is told nothing. `DESIGNDOC.md`'s **Extending** section says which table
each kind of new thing belongs in, and what else it owes.
