# Bosses: attacks, patterns and phases

A reference to read and iterate on. It covers every attack each boss has, what
tells you it is coming, the numbers behind it, how the boss picks between
attacks, and what changes from one phase to the next. Every number comes from
the code as it stands. "Knobs" points at the table to edit.

The *why* behind these numbers is in `DESIGNDOC.md` (**The bosses**) and in the
comments over each row in `src/enemy.lua`. This file only describes the fights.

---

## The shared frame

| | |
| --- | --- |
| **When** | At 10:00 of each cycle (`Spawner.BOSS_AT = 600`). Drills and surges are cleared and the horde stops spawning. |
| **Two to a lesson** | At Masters and PhD (`bosses = 2` in `src/course.lua`) a lesson with an `encore` (`src/subjects.lua`) is two cycles: its boss ends the first, "NOT DONE YET" is said, the box comes down and ten more minutes of horde follow, then the encore ends the second. Only the encore opens the win card (`Spawner:lessonOver`). Endless repeats the pair. Today SCIENCE has one (the Atom), FINANCE has one (the Piggy Bank), MATHS has one (the Tesseract), MUSIC has one (the Speaker) and GRAMMAR has one (the Red Pen). |
| **Arena** | `Game:openArena` puts a box round the page. The box comes down when the next cycle starts (`Spawner:nextCycle`). |
| **Escort** | One arrival every 1.5s while fewer than 20 enemies are on the page. Weighted: bat 5, skull 3, eye 2, wad 2, bulb 2 (`ESCORT` in `src/spawner.lua`). |
| **Health** | 900 on every row × `1.4^cycle` × the course's `hp`. In cycle 1 that is **1260** (High School), 1575 (Bachelor), 2016 (Masters), 2646 (PhD). Bosses sit outside the horde's per-minute health curve. An encore arrives in cycle 2, so the Atom, the Piggy Bank, the Tesseract, the Speaker and the Red Pen are 2822 (Masters) and 3704 (PhD). |
| **Damage** | Contact damage is 20 on every boss and steps ×1.18 per cycle (`DAMAGE_PER_CYCLE`). Move damages on the rows are cycle-1 values and scale the same way. |
| **Body** | All bosses share `knock = 0.06` and `hold = 0.3`. Every boss is worth 250 xp. |
| **Phases** | Health thirds: phase 1 above 66%, phase 2 above 33%, phase 3 for the rest. A list of three values on a row is one value per phase. The whistle is the exception: it has no phases, only health thresholds at 75/50/25%. |
| **Selection** | Most brains take a weighted random pick based on your distance. The last move is multiplied by about 0.12–0.15 and the one before it by 0.6, so the same move rarely comes twice in a row. |
| **Glue** | Every boss has a glue answer, listed per boss below. In most cases glue cancels a tell that is still winding up and puts the boss into a rest. |

### At a glance

| Boss | Subject | "About" | Moves | Unlocks later | Signature tell |
| --- | --- | --- | --- | --- | --- |
| The Eye | SCIENCE | ground | stare, bowl, slam, sink, weep | sink, weep (phase 2) | the 3D eye looks where it will hit |
| The Whistle | P.E. | the air and the class | lunge, blast, jacks, squad, pump (clocks) | none (pump at 75/50/25%) | stands still blinking red |
| The Metronome | MUSIC | time | sweep, chord, scale | scale (phase 2) | one full bar of count-in, weight blinks red |
| The Stamp | FINANCE | cells | slam, run, audit | audit (phase 2) | rocks back on its heel, cells outlined |
| The Dictionary | GRAMMAR | lines | clap, riffle, definition | definition (phase 2) | front board lifts (mouth open) |
| The Die | MATHS | number | throw → roll → strike | shape changes d6 → d10 → d20 | the face it lands on |
| The Still Life | ART | light | shade, drop, roll, top | roll (phase 2), top (phase 3) | the lamp moves, shadows grow |
| The Atom | SCIENCE (encore) | orbits | sweep, throw, fission | splits in two at 50%; double sweeps in the last fifth | a dashed red ring on the floor where the orbit will swell |
| The Piggy Bank | FINANCE (encore) | greed | charge, recall, shatter | two charges in a row (phase 2); breaks open at 30%, then three charges and no bait | it turns its snout to you, a dashed red arrow down its lane |
| The Tesseract | MATHS (encore) | dimension | inside-out, corners, net, fold | fold and the second, inverted flip (phase 2); turning squares, double volley, shuffled net (phase 3) | its shapes drawn on the floor first: two squares, a numbered net, a dashed square on you |
| The Speaker | MUSIC (encore) | volume | drop, roll, shuffle, pair | pair (phase 2); thump on every downbeat, double shuffle, the drop's gap reverses (phase 3) | a bar of build-up, its ring of lights red, the quiet gap drawn in blue |
| The Red Pen | GRAMMAR (encore) | corrections | wrong (ring), strike-through (fall), shake, grade | the grade and a roll after a fall (phase 2); two rings, two falls, two flicks, the F circled (phase 3) | a dotted ring round you, a strip as long as it is across the page, the F's strokes dashed in |

---

## 1. The Eye: SCIENCE (`bosseye`)

**Files:** row at `src/enemy.lua:317`, brain at `src/eyeboss.lua`, body at `src/eyeball.lua`
**Callout:** "THE EYE IS OPEN" · **Body:** radius 20, speed 26 (yours is 58)

### Entrance
It drops from 170px above the page onto a marker 100px from you, clamped into
the box, over 0.95s. The landing throws a dust ring that does no damage. It then
lies with its eye shut for 0.75s, opens it on you, and walks for 1.0s before its
first move.

### Always on (clocks, paused while a move is playing)
| Attack | Pattern | Numbers |
| --- | --- | --- |
| **Fan** (`shot`) | 5 red teardrops in a 1.05 rad arc, aimed at you | every 2.6s, range 190, speed 46, 12 dmg |
| **Trail** | It leaves wet puddles behind it as it walks | every 0.5s, 9px apart, r12, lasts 7s, 6 dmg |
| **Scatter tears** | 3 tears lobbed anywhere in the box, landing 34–130px out. These are not aimed at you. | every 3.2s |
| **Lane tears** | 5 tears down the line to you, landing at 26, 50, 74, 98 and 122px. They make a wall across your path. A tear welling at the lid is the tell (last 0.7s). | every 7.5s |
| **Ring tears** | A full ring of 14 tears at 50px | once each at 66% and 33% health |
| **Brood** | 2 small `eye`s at 66%, 2 `redeye`s at 33% | with the rings |

A tear is **lobbed**. Its shadow tracks the landing spot, and it only hurts as it
comes down. It deals 8 and leaves a puddle (r10, 5.5s, 6 dmg).

### Moves (`attacks`)
Between moves it walks toward where you are going to be: your position plus 0.6s
of your smoothed velocity. The gap between moves is `cool` = **2.6 / 2.0 / 1.5s**
plus up to 0.6s.

| Move | Tell | Attack | Phase scaling | Rest |
| --- | --- | --- | --- | --- |
| **Stare** | Stops and glares. A dotted line swings toward you (2.4 rad/s) for `aim`, then goes **solid and stops tracking** for `lock`. Stepping off the line during `lock` dodges it. | A beam 260 long and 5 wide, 14 dmg, lasting `fire`. From phase 2 the beam keeps sweeping the way it was turning, so step *against* the swing. | aim 0.85/0.75/0.65 · lock 0.5/0.42/0.36 · fire 0.45/0.55/0.65 · sweep 0/0.35/0.55 rad/s | 0.6 |
| **Bowl** | Red blinking rim and an arrow for `wind`. The line locks at the start, leading you by 0.3s. | Rolls down the line at 104 for 1.7s, smearing a wet streak and bouncing off the box walls. | wind 0.75/0.65/0.55 · bounces 0/1/2 | 0.9, dizzy |
| **Slam** | Crouches for 0.4s, then 0.85s in the air (46px high) toward where you will be (reach 150), with a marker on the ground the whole time | Lands in a shock ring. 12 dmg. From phase 2 it also throws a ring of tears (44px reach). | shock radius 48/54/60 · leaps 1/1/2 · tear ring 0/8/10 | 0.7 |
| **Sink** *(phase 2+)* | Goes down into a puddle (0.45s). The surfacing spot bubbles while it is under (0.4s). | Comes up out of another puddle 45–140px from you (0.35s). In phase 3 it surfaces with a ring of 8 tears (40px). | ring 0/0/8 | 0.5 |
| **Weep** *(phase 2+)* | Looks up and a tear wells for 0.7s | `volleys` rings of `count` tears, the first at 38px, each ring 30px further out and turned half a gap, 0.35s apart. The gaps never line up, so the way out is a zigzag. | volleys 0/3/4 · count 0/8/10 | 0.7 |

**How it picks** (`EyeBoss:choose`, `src/eyeboss.lua:269`), where d is your distance:
- stare: 1.2 if d > 70, else 0.35; ×1.3 if you are moving faster than 30
- bowl: 1.1 if 45 < d < 190, else 0.3
- slam: 1.6 if d < 95, else 0.6
- sink (needs a puddle to come up from): 1.4 if d > 130, else 0.6; **×3 if it is stuck** (moved less than 14px in 1.6s)
- weep: 1.0 if 45 < d < 170, else 0.45; ×1.5 if your speed is under 20
- Last move ×0.12, the one before ×0.6

### Phase changes
- **→ 2 (66%):** it flinches, blinks and knocks the camera (2). The tear ring and 2 eyes arrive. Sink and weep unlock. The beam starts to sweep. Bowl gains a bounce. Slam adds a tear ring.
- **→ 3 (33%):** the same flinch, a harder knock (3), and the iris turns **red**. The tear ring and 2 redeyes arrive. Slam leaps twice. Sink surfaces with a ring. Weep throws 4 volleys.

### Glue
Glue during any wind-up (stare aim or lock, bowl wind, slam crouch, sink down,
weep well) **drops the move**. The eye goes dizzy and open for 0.4s.

### Death
It shivers for 0.9s, then bursts into puddles that do no damage. The win card
shows 1.6s later. You cannot be hurt while it dies (`player.truce`).

---

## 2. The Whistle: P.E. (`whistle`)

**File:** row at `src/enemy.lua:448`, all behaviour in `Game:updateWhistle`
**Callout:** "THE WHISTLE BLOWS" · **Body:** radius 13, speed 22

The Whistle has **no brain and no phases**. Every attack runs on its own clock,
and the only escalation is the pump at three health thresholds.

| Attack | Tell | Pattern | Numbers |
| --- | --- | --- | --- |
| **Spit** (`shot`) | none | 3 peas in a 0.42 rad arc, aimed at you | every 1.9s, range 200, speed 58, 9 dmg |
| **Lunge** (`charge`) | Stands still with a red outline for 0.85s. The line locks at the start of the wind-up. | Dashes at 140 for 0.6s (84px), then rests 1.4s | every 7s, only when you are within 150 |
| **Blast** | Stands still blinking red and shuddering for 0.9s, with red rings going out | 2 rings of 22 notes, 0.3s apart, with a 4-note gap at the **same angle** in both. The second ring is offset half a note. Get into the gap. | every 6s, speed 55, 10 dmg, notes live 4.5s |
| **Jacks** | Graphite cross on each landing spot | 6 jacks lobbed to land within 50px of you (0.9s flight). Each becomes a spike that hurts on contact for 7s and blinks out over its last second. | every 4.6s, 8 dmg |
| **Squad** ("FALL IN!") | none | A wall of 6 of one kind, 18px apart, marched across the box from one of its 4 square edges. The kind cycles skull → wad → blob → bat. | every 12s, only while there are fewer than 28 enemies |
| **Pump** ("GROW!") | Long note, red rings | The 3 nearest ordinary enemies within 170px become **champions** in place. Any it could not find are spawned beside it as champions. | at 75%, 50%, 25% health |

**Rules:** a blast never starts during a lunge, and the lunge's clock pauses
during a blast, so the two red tells never overlap. Glue holds all four calls
(blast, jacks, squad, pump).

---

## 3. The Metronome: MUSIC (`metronome`)

**Files:** row at `src/enemy.lua:519`, brain at `src/metronome.lua`
**Callout:** "THE METRONOME TICKS" · **Body:** radius 12, speed 50, but it hops for half of each beat, so it averages about 25

Everything happens **on the beat**. Tempo is **60 / 80 / 100 bpm** by phase, at 4
beats to the bar, and it says "FASTER!" at each phase change. The state machine
`idle → count → play → rest` only moves on whole bars. Every move gets **one full
bar of count-in** at the tempo it will be played at: 4.0s at 60 bpm, 3.0s at 80
and 2.4s at 100. The weight on the arm blinks red through the count-in, and the
tick is pitched up on beat one.

### Idle
It roams around you at about 70px (keep 85, aims 0.6 rad further round than it
stands, changes direction every 3 bars) and fires **a note at you every 2 beats**
(speed 62, 9 dmg). Between moves it waits **2 / 1 / 1 bars**, and rests 1 bar
after each move. It keeps roaming through rests and the scale. It plants only for
the sweep and the chord.

| Move | Count-in (1 bar) | Played | Numbers |
| --- | --- | --- | --- |
| **Sweep** | A fan of ±0.8 rad toward you, 150 long, dashed on the floor. A ghost beam already swings with the arm. The body plants facing the fan. | A beam swings across the fan with the arm. Leave the fan; you cannot outrun the beam. | 5 wide, 14 dmg · bars 1/1/2 |
| **Chord** | Rings at 30 / 66 / 102 (/138) dotted round where it stands. The first one blinks on the last beat. | One ring strikes per beat, inside out. Each band is 12px wide with 24px of safe room between bands. The next ring blinks before it goes. | rings 3/3/4 · 14 dmg |
| **Scale** *(phase 2+)* | A wall of notes 16px apart along the box edge on the far side from you, with a **3-note gap** where you are | Marches across the box in 8 beat-steps. The gap climbs one note per beat: the note at its leading edge jumps to the trailing edge. | 10 dmg · 2 bars |

**How it picks** (`Metronome:choose`, `src/metronome.lua:251`):
- sweep: 1.4 if 40 < d < 150, else 0.5
- chord: 1.5 if d < 110, else 0.6
- scale (phase 2+): 1.4 if d > 90, else 0.8
- Last move ×0.15, the one before ×0.6

**Glue** stops the clock. Nothing advances while it is frozen. A count-in in
progress is dropped and becomes a rest until the next downbeat. Notes already in
the scale wall get their lost time back.

---

## 4. The Stamp: FINANCE (`stamp`)

**Files:** row at `src/enemy.lua:587`, brain at `src/stamp.lua`
**Callout:** "THE STAMP COMES DOWN" · **Body:** radius 13. It never walks; every step is a leap.

It works in **ledger cells**: 5 columns of 40px and rows of 12px, matching the
FINANCE page. Each move outlines and hatches its cells first, then leaps there.
Contact damage applies only in `idle` and `rest`. During moves, only the pad
hurts.

**Ink:** a stamped cell stays **wet** for the time the move sets, dealing 6 to
stand in, then dries for 6s and does nothing. Stamping a cell again re-wets it.

### Idle
It rocks back for 0.18s, then hops up to 30px at you every **1.2 / 1.0 / 0.85s**.
It flicks an ink **blot** at you every 2.6s (speed 62, 9 dmg). The wait between
moves is **2.2 / 1.7 / 1.3s**.

| Move | Tell | Attack | Phase scaling | Rest |
| --- | --- | --- | --- | --- |
| **Slam** | Rocks back for `rear`. Your cell blinks and **follows you** until the lock. | A 0.55s leap (34 high) onto the locked cell. 16 dmg, ink wet for 2.4s, knockback. | rear 1.0/0.85/0.7 · splash blots in a ring 0/6/8 | 1.1/1.0/0.85 (stuck) |
| **Run** | Rocks back for 0.7s with the first cell outlined | Hops one 40px cell every 0.22s along a row (about 180px/s), stepping one row toward you on each hop and turning back at the box edge. 12 dmg, wet 1.8s. | hops 5/6/8 | 0.9 |
| **Audit** *(phase 2+, "AUDIT!")* | A **chequerboard** over a 5×9 block round you (5×11 in phase 3), hatched for 1.3s | Stamps every other cell 0.14s apart (0.12 in phase 3), one row at a time, snaking back along the next. All of it stays wet until 0.6s after the last stamp. 12 dmg. | Phase 3: **two passes**. The second pass hits the other colour, counted in for 1.2s, and the first pass's ink dries halfway through. | 1.2 |

**How it picks** (`Stamp:choose`, `src/stamp.lua:335`):
- slam: 1.5 if d < 140, else 0.8
- run: 1.3 if d > 50, else 0.6
- audit (phase 2+): 1.1 flat
- Last ×0.15, before ×0.6

**Phases:** it says "AUDIT!" at 66% and "FASTER!" at 33%.
**Glue:** it drops whatever it is doing. A leap ends where it is with no stamp,
and the Stamp takes a short rest.

---

## 5. The Dictionary: GRAMMAR (`dictionary`)

**Files:** row at `src/enemy.lua:645`, brain at `src/dictionary.lua`
**Callout:** "THE DICTIONARY OPENS" · **Body:** radius 14. It never walks.

It works in **groups of the paired ruling**: 30px groups, with 12px lines inside
them. It is the Stamp's skeleton with different attacks. The front board lifting
(the mouth opening) is the tell for everything it does. Contact damage applies
only in `idle` and `rest`.

**Writing:** wet ink deals 12 to stand in, then dries for 5s. The words written
are the five parts of speech.

### Idle
The board goes up for 0.22s, then it hops up to 30px at you every
**1.2 / 1.0 / 0.85s**. It flicks a **leaf** at you every 2.6s (speed 62, 9 dmg).
The wait between moves is **2.2 / 1.7 / 1.3s**.

| Move | Tell | Attack | Phase scaling | Rest |
| --- | --- | --- | --- | --- |
| **Clap** | Board up for `rear`. Two pages, `reach` wide and `lines` groups deep, follow you as dashes. The spine is placed half a page short of you. | A 0.5s leap (30 high) onto the spine, landing **open**. It stays open for `hold`, then both fore-edges close to the spine over 0.3s: 16 dmg to anything an edge passes over. | rear 1.0/0.85/0.7 · reach 80/90/100 · lines 2/2/3 · hold 0.55/0.45/0.35 · splash leaves 0/6/8 | 1.2/1.0/0.9 (stuck) |
| **Riffle** | Board up for 0.8s | `turns` page turns, each a fan of `leaves` leaves 0.3 rad apart, aimed where you were when that turn started. Every other fan is offset half a gap. | turns 5/6/8 · every 0.42/0.38/0.34s · leaves 5/7/7 | 0.9 |
| **Definition** *(phase 2+, "DEFINITION!")* | The lines of every group within `rows` of yours are dashed across the box, with the pen blinking at the start, for 1.3s | Written left to right at **180px/s** (over 3× your speed, so step off the line). Each line starts 0.2s after the one above. Ink stays wet until 0.8s after the last letter. 12 dmg. | rows 2/2/3 · Phase 3: **second pass written between the lines**, counted in for 1.2s | 1.2 |

**How it picks** (`Dictionary:choose`, `src/dictionary.lua:229`):
- clap: 1.5 if d < 150, else 0.9
- riffle: 1.2 if d > 60, else 0.6
- definition (phase 2+): 1.0 flat
- Last ×0.15, before ×0.6

**Phases:** it says "DEFINITION!" at 66% and "FASTER!" at 33%.
**Glue:** it drops whatever it is doing. A leap ends where it is, a clap is let go
without shutting, and a half-written pass is left to dry.

---

## 6. The Die: MATHS (`die`)

**Files:** row at `src/enemy.lua:710`, brain at `src/diceboss.lua`, body at `src/dice.lua`
**Callout:** "THE DIE IS CAST" · **Body:** radius 14. It never walks; every move is a throw.

The Die makes **no choices**. Each cycle is the same loop, and **the face it lands
on decides the attack**. The number rolled hangs on a tag over it while it acts.

### The loop
1. **Wind:** the line is locked and dashed on the floor, aimed within ±0.3 rad of
   you. It shudders and blinks red for **0.75 / 0.65 / 0.55s**.
2. **Tumble:** slows linearly from `speed` to 0 over `time` (**150/165/180** over
   **1.3/1.25/1.2s**), so it stops 97–108px away. Its peak speed is about 3× yours,
   so step off the line. It makes 3 hops on the way, bounces off the box, and
   spins randomly so the result is a genuine roll.
3. **Settle** on a face.
4. **Show:** strikes play from a queue, each with a tell and then a hot phase,
   followed by the pip volley.
5. **Rest:** **1.5 / 1.3 / 1.1s**.

### What each roll does
| Phase | Shape | Roll | Strike | Then |
| --- | --- | --- | --- | --- |
| 1 | **d6** | 1–6 | **Stamp:** a 3×3 grid of 30px cells round you. The cells where that face's pips sit go hot. Tell 1.2s, hot 0.35s, 14 dmg. | a **fan** of N pips at you (0.22 rad apart, speed 66, 9 dmg) |
| 2 | **d10** | 1–10 | **Checker:** every 20px cell in the box whose column + row has the roll's parity. A safe cell is always one cell away. Tell 1.1s, hot 0.35s, 12 dmg. | a **ring** of N pips |
| 3 | **d20** | 2–19 | **Spokes:** N lines out from it to the box edge (5 wide, 260 long), which swing a third of a gap while hot. A ghost of the swing loops during the count-in. Tell 1.0s, hot 0.6s, 12 dmg. | none |
| 3 | d20 | **20** | **"CRITICAL!":** 20 spokes, then odd cells, then even cells, with count-ins of 1.0, 0.8 and 0.6s | none |
| 3 | d20 | **1** | **"FUMBLE!":** lies on its side seeing stars for 3s and takes **×1.5 damage** | none |

### Shape changes (phase transitions; glue cannot interrupt these)
- **Unfold at 66% ("MORE SIDES!"):** it shudders for 0.5s, then disappears and
  cannot be hit. A **net** (a cross of six 40px faces) is laid round where it
  stood: counted in for 1.0s, hot for 0.4s at 14 dmg, then folded up over 0.3s.
  It comes back as a d10.
- **Recast at 33%, or straight from the d6 if both thresholds pass at once:** it
  rises 220px over 0.45s. Its shadow and a dotted shock ring sit on where you
  stood for 1.1s (about 90px of walking against a 56px ring, so you only get hit
  by standing still). It comes down in 0.25s as a d20, with the ring hot at
  14 dmg, and the landing becomes a roll.

**Glue:** it drops any strike that is still counting in and rests. Glue that hits
while the die is **tumbling or settling** loads the roll so it lands on **1**. On
the d20 that is a guaranteed fumble.

---

## 7. The Still Life: ART (`stilllife`)

**Files:** row at `src/enemy.lua:781`, brain at `src/stilllife.lua`, body at `src/plaster.lua`
**Callout:** "DRAW WHAT YOU SEE" · **Body:** radius 16. A plaster cube, sphere and cone under a lamp.

**Movement:** it never walks. When you are more than 90px away and nothing else
is happening, it **lifts the table** and puts it down up to 60px closer (never
nearer than 50), in a 0.45s hop.

**The lamp** sits 80px out, clamped into the box, and drifts at 0.35 rad/s when
no move is using it. Every piece on the table throws a shadow wedge away from the
lamp. At rest the wedges are short and graphite, and they do no damage.

### Moves run side by side
This is the only boss that **overlaps its own attacks**. A new move starts `cool`
(**2.0 / 1.6 / 1.3s**) after the last one started, as long as fewer than
`together` (**1 / 2 / 3**) are running. Each piece does one thing at a time,
only one shade can run at a time, and the move it started last is avoided when
another is free. The pick among available moves is uniform, with no distance
weighting.

Pieces off the table are **hittable**. A stand-in enemy follows each one, and any
damage dealt to it goes to the boss.

| Move | From | Tell | Hot | Numbers |
| --- | --- | --- | --- | --- |
| **Shade** | phase 1 | The lamp eases round to the far side of the group from you (±0.35). The wedges grow from 14 to 320 long, hatched with marching rows and edged slate, turning red for the last 0.35s. | The wedges fill slate with red edges, 12 dmg to stand in. The lamp keeps going `swing` further round, so the shadows sweep (about 46px/s at 200 out). The space between the lamp and the group is always safe. | tell 1.4/1.25/1.1 · hot 0.9/1.3/1.5 · swing 0/0.3/0.3 · phase 3: **second lamp** 2 rad round throws a second fan |
| **Drop** (cube) | phase 1 | The cube rises 200px off the table and out of sight (0.4s). A dotted shock ring and a growing shadow sit on where you stood for 1.1s. | It comes down square in 0.22s, ring hot, 14 dmg. It then **sits** for 1.4s as a block that hurts to touch and can be hit, then hops home (0.5s). | shock 24 |
| **Roll** (sphere) | phase 2 | The line is dashed to the box edge and it shudders for 0.75s | Rolls out at 170 to the edge (or 260 max) and back at 0.8× that speed, hurting on contact (14) | |
| **Top** (cone) | phase 3 | The cone flips end over end in the air (0.45s) | It spins on its point, leaning 0.3 and wobbling, and **wanders after you at 46** (you move at 58). It throws a chip every 0.16s, each 2.4 rad further round, making a spiral of pips (speed 60, 9 dmg). Then it falls on its side (0.35s) and is stood back up at home (0.55s). Contact deals 12. | time 2.6/2.6/3.2s |

### Phase changes
At each third **every move is dropped** and every piece is put back on the table.
- **→ 2 ("THE LAMP MOVES!"):** the shade starts to sweep, the sphere joins, and up to 2 moves can run at once.
- **→ 3 ("ANOTHER LAMP!"):** a second lamp is added, the cone joins, and up to 3 moves can run at once.

**Glue holds the table, not the pieces already off it.** A shade still counting
in is dropped, a lift is put down where it is, and no new move starts. A cube
already in the air, a sphere already rolling or a cone already spinning carries
on.

---

## 8. The Atom: SCIENCE's encore (`atom`)

**Files:** row `atom` in `src/enemy.lua`, brain at `src/atomboss.lua`, body at `src/atom.lua`
**Callout:** "THE ATOM IS UNSTABLE" · **Body:** radius 12 (the nucleus only; a shot through the orbits misses). Speed 22.
**When:** Masters and PhD only, ten minutes after the Eye goes down.

### Entrance
It walks on from the ring like the others and **forms**: its three orbits grow out
of the nucleus over 1.2s, during which nothing about it hurts except contact.

### Always on
Three orbits at 22 / 28 / 34 out, each tilted off the page and swinging round
(0.35–0.55 rad/s), each with an electron going round at 2.4–3 rad/s. **Touching an
electron deals 8** (hit radius 2). Between moves (`rest`) every orbit is given a
new tilt between 0.2 and 1.4 rad, so the next sweep is never the last one's shape.

### Idle
The whole atom walks straight at you. After fission, each half walks **round** you
64px out, aiming 0.6 rad further round than it stands, so the two hold opposite
sides of you. Cool between moves: **2.4 / 2.0 / 1.5s** + up to 0.6s.

### Moves
The pick is weighted by distance: sweep 1.4 if you are inside 1.1× its reach (else
0.6), throw 1.2 beyond 60px (else 0.5). The last move is ×0.35.

| Move | Tell | Hot | Numbers |
| --- | --- | --- | --- |
| **Sweep** | The orbit blinks; a dashed red ring is drawn on the floor at the size it will swell to, already swinging the way it will. The nucleus shivers. | The orbit swells out in 0.3s to `reach` and is a red band (width 3, **14 dmg**) for 2.6s with three electrons racing round it, then falls back in 0.3s. It is tipped to one of three lies: **0.25** (near face on: a wall round the atom), **0.95** (an ellipse sweeping round) or **1.4** (near edge on: a turning bar). | reach 90 / 72 / 72 · tell 0.95 / 0.85 / 0.7 · swing 0.5 / 0.55 / 0.65 rad/s (~50px/s at the tip of a 90 ring) · orbits at once 1 / 1 / 2 · rest 0.9 / 0.8 / 0.6 |
| **Throw** | The orbit blinks red with its electron on it | The electron leaves on a curve and **homes**: speed 44 (you move at 58), turning at most 1.7 rad/s, gone after 5s, **9 dmg**. Its orbit is empty for 3s. | tell 0.65 / 0.55 / 0.5 · count 1 / 1 / 2 · rest 0.6 / 0.5 / 0.4 |

### Phases
Not thirds. Phase 1 is the whole atom; phase 2 is the two halves; phase 3 is the
last fifth of their combined health. The HUD bar is the halves together.

- **Fission (at 50%):** only from idle or a rest, so it never cuts a sweep off.
  "FISSION!", 1.1s of shudder and stretch, then two halves (nucleus 19 across, hit
  radius 8, two orbits at 16 / 22) sharing the health left, flung apart at 110 for
  0.45s at right angles to you. The second half rests 1.2s longer so the two do not
  count in together.
- **→ 3 (20% left):** a knock and a burst; shorter tells and two orbits per sweep
  and two electrons per throw, from each half.

### Glue
Cancels a sweep or a throw still being counted in, and it rests for 0.4s.

### Death
Killing the half the bar is hung off moves the bar to the other (`AtomBoss:heir`).
The lesson ends when the second half goes down: no death animation, a burst, then
the win card.

## 9. The Piggy Bank: FINANCE's encore (`piggy`)

**Files:** row `piggy` in `src/enemy.lua`, brain at `src/piggyboss.lua`, body at `src/piggy.lua`
**Callout:** "THE PIGGY BANK IS FULL" · **Body:** radius 14, speed 30.
**When:** Masters and PhD only, ten minutes after the Stamp goes down.

### Coins
Everything it does puts coins on the page, and **they are real**: each one you
walk over is one coin in the purse at the end of the run (`banked`, a term of
`Purse.forRun` outside the course's multiplier, kept across a bookmark). A coin on
the floor is a pickup (`coin` in `src/pickup.lua`, never scattered, never counted
against the scatter cap) and stays on the page after the fight. A coin in the air
is the brain's until it lands.

### Entrance
It walks on from the ring like the others, stands rattling for 0.9s facing you,
then trots for 0.8s before its first move.

### Idle
Trots straight at you, turning its body to face the way it is going (5 rad/s).
Cool between moves: **2.2 / 1.8 / 1.2s** + up to 0.6s.

### Moves
Charge weighs 1.2 (×0.6 straight after a charge). Recall weighs 0.6 + 0.12 per
coin on the floor of the box, needs at least 3, never follows itself, and is gone
once it is broken.

| Move | Tell | Hot | Numbers |
| --- | --- | --- | --- |
| **Charge** | Plants and faces you, nose down; the wad's blinking red rim; a dashed red arrow 90 long down the locked lane. During the wind it spits **bait** coins out of its slot, lobbed (0.45s) into the lane 34px out and every 22px after. | Runs the lane at **140** (you move at 58), bouncing off the box walls; a pen line stops it dead. Contact is the usual 20. Then stands dizzy. | wind 0.9 / 0.8 / 0.65 · charges in a row 1 / 2 / 3 (later ones wound for 0.45, no bait) · bait 3 / 4 / 0 · up to 1.5s · bounces 0 / 1 / 1 · dizzy 1.0 / 0.85 / 0.7 |
| **Recall** ("savings") | Rears up, nose in the air; every coin on the floor of the box blinks red in a ring with a dashed line home. Coins picked up during the tell are yours. | Every called coin slides back to its slot at once, red, **8 dmg** to anything in the way (a coin that hits you is spent). Out after 3s at most. | tell 1.0 / 0.85 · speed 105 / 120 · rest 0.6 / 0.5 |

### Phases
Phase 1 above 65%; phase 2 below it; phase 3 once it has shattered.

- **Cracks** spread across its back from one spot as it is hurt (from about 12%
  gone), the body's way of showing the phases coming.
- **Shatter (at 30%):** only from idle or a rest. 1.1s of shaking harder and
  harder, then "BANKRUPT!": the shards round the crack's first spot are gone and
  it bursts **3 rings of 14 coins**, 0.4s apart, each with a 2-coin hole and turned
  half a step from the last. Coins fly at **85**, **9 dmg**, and land 60–110px out
  as pickups. Then it rests 1.0s.
- **3 (broken):** no bait and no recall; three charges in a row, shorter cools.

### Glue
Cancels a charge wind or a recall still being counted in, and it rests 0.4s. Bait
already spat stays on the floor; a charge in progress stops when glued in place.

### Death
A burst of pink shards. Whatever coins were in the air land where they are, and
**6 more spill out** round it, harmless. Then the win card (or, on ENDLESS, the
next cycle with the coins still on the page).

## 10. The Tesseract: MATHS's encore (`tesseract`)

**Files:** row `tesseract` in `src/enemy.lua`, brain at `src/tesseractboss.lua`, body at `src/tesseract.lua`
**Callout:** "THE FOURTH DIMENSION" · **Body:** radius 15, speed 20.
**When:** Masters and PhD only, ten minutes after the Die goes down.

### Entrance
It walks on from the ring like the others, then turns into the page out of
nothing over 1.3s, spinning down from six times its pace, and drifts for 0.8s
before its first move. It can be hit while it forms.

### Idle
Drifts straight at you, slower than anything else on the page. It turns
through four dimensions the whole time, faster the more it is hurt. Cool between
moves: **2.3 / 1.9 / 1.5s** + up to 0.6s.

### Moves
Flip weighs 1.4 when you are within 1.1 × the outer square, 0.4 otherwise. Corners
weigh 1.1 past 50px (0.6 nearer). The net is 0.9 always. Fold, from phase 2, is
2.0 past 110px and 0.2 nearer. The last move is ×0.3.

| Move | Tell | Hot | Numbers |
| --- | --- | --- | --- |
| **Inside-out** | It shivers and nearly stops turning. Two dashed squares on the floor round it, turned the way the cube is turned, the band between them dotted red. | It turns half over through w (the inner cube becomes the outer). The band between the squares is red for 0.45s: **14 dmg**. The crowd caught in it is flung out (260). | inner square 30 out · outer 84 / 92 / 100 · tell 1.1 / 0.95 / 0.85 · rest 0.9 / 0.8 / 0.6 |
| **Inside out** (phase 2+) | Straight after the flip, 0.75s: the middle square and a 36px rim outside the outer square are dotted. | The middle and the rim go off. The band you dodged into is the only floor that stays safe. | same numbers |
| **Corners** | It nearly stops turning. The outer 8 corners (all 16 from phase 2) blink red. | Each corner flies straight out the way it sticks out on the page, the furthest at **80** and the nearest at 40 (you move at 58): **9 dmg**, life 4s. | tell 0.8 / 0.7 / 0.6 · volleys 1 / 1 / 2 (the second spun on 0.35s and aimed 0.45s) · rest 0.7 / 0.6 / 0.5 |
| **Net** | It unfolds a net of eight cubes, 30px each (three of the page's squares), from the square it hovers over towards you. The net is a cross: a column of four with two arms either side of the second. The cubes are numbered 1–8, and the next to go blinks. | Each cube goes red in its number's order, **0.5s each**, **14 dmg**. Then the net folds back up. | opens 0.5 · first after 0.7 more · one every 0.42 / 0.36 / 0.3 · order: root→tip / tip→root / shuffled |
| **Fold** (phase 2+) | It shrinks and spins out of the page over 0.5s. A dashed spinning square marks where you stood (clamped into the box), with a grey square closing in on it. | It is back there in 0.2s with a square shock **34 out**: **14 dmg**. While it is out it can't be hit and has no contact damage. | aim 1.1 / 1.0 / 0.9 · rest 0.9 / 0.8 / 0.7 |

### Phases
Thirds, as the die.

- **2 (66%):** fold joins, the flip turns back inside out straight after, the
  corners volley is all sixteen, and the net runs from the tip back to the root.
- **3 (33%):** "HYPERSPACE!", and 1.2s of spinning at triple speed. The flip's
  squares turn 0.6 rad while they go off, two volleys of corners, and the net goes
  off in a shuffled order: read the numbers.
- From about 60% hurt one of its edges now and then jumps a pixel or two out of
  place in red for a few frames. Its blush heart goes denser at a third, and red
  at two thirds.

### Glue
Cancels an inside-out or a volley still being counted in, or a net none of whose
cubes has gone off yet, and it rests 0.4s.

### Death
A burst at each of its sixteen corners, and a knock. Then the win card.

## 11. The Speaker: MUSIC's encore (`speaker`)

**Files:** row `speaker` in `src/enemy.lua`, brain at `src/speakerboss.lua`, body at `src/speaker.lua`
**Callout:** "NOW PLAYING" · **Body:** radius 13, speed 24 (it bounces at you on the beat).
**When:** Masters and PhD only, ten minutes after the Metronome goes down.

### Entrance
Dropped onto the page (`arrive`), then it switches itself on: its ring of twelve
lights comes up one at a time with twelve rising ticks over 1.2s, then a thump, a
puff and its first notes. It bounces for 0.8s before its first move.

### The beat
**112 / 124 / 136 bpm** by phase. On every beat it bounces off the page and
squashes as it lands, its radiator pumps, a puff goes round its foot, and every
other beat a note floats up; a kick on every bar. Moves are not counted in on the
beat (only the drop's build and the pairing's fuse are counted in beats). Glue
**mutes** it: the beat stops and its lights go out.

### Idle
Bounces straight at you, turned so its + faces you. Cool between moves:
**2.2 / 1.8 / 1.4s** + up to 0.6s.

### Moves
Drop weighs 1.2. Roll 1.3 past 60px (else 0.6). Shuffle 1.0. Pair, from phase 2,
1.4 when at least 2 of the crowd are within 150 of you (else 0). The last move is ×0.3.

| Move | Tell | Hot | Numbers |
| --- | --- | --- | --- |
| **Drop** | 4 beats of build: it stretches tall and trembles, its lights blink red faster and faster, the ticks rise and double into a roll. The first ring's quiet gap is a blue dashed wedge, off to one side of you. | "DROP!": the crowd within 90 is thrown back (260) and a ring goes out across the whole box, then one per beat. Each ring is red with a gap; outside the gap it hits **12** once as it crosses you. The gap steps round each beat, and the next is always drawn in blue. Rings push the crowd they cross (110). | rings 6 / 8 / 10 · speed 84 / 92 / 100 · gap 1.1 / 1.0 / 0.85 rad · step 0.36 / 0.34 / 0.32 rad a beat (about 40–44px/s at 60 out) · phase 3: the step reverses half way · rest 1.0 / 0.9 / 0.7 |
| **Roll** | The wad's blinking red rim, a dashed lane 90 long, and it tips onto its side. | Rolls down the lane at **130 / 140 / 150**, off the box walls (it turns with each bounce), throwing the crowd out of the lane (220). Contact is the usual 20. Then 0.5s standing back up: the window. | tip 0.75 / 0.65 / 0.55 · bounces 1 / 2 / 3 · up to 2.2s · a pen line stops it · rest 0.8 / 0.7 / 0.5 |
| **Shuffle** | It spins, lights chasing, its handful of notes going round its top. | A ring of notes out of its top that **bounce off the box walls** at 52 (slower than you) for 4.5s, **9 dmg**, blinking out at the end. | tell 0.7 / 0.6 / 0.5 · notes 5 / 6 / 7 · handfuls 1 / 1 / 2 (0.45s apart, turned half a step) · rest 0.7 / 0.6 / 0.5 |
| **Pair** (phase 2+) | It turns its back (the bluetooth rune blinks), its lights go blue, a dashed link to each of the nearest 3 / 4 of the crowd within 150 of you, and a red dotted ring 28 round each. | On the beat, every paired thing still alive goes off: **10** within 28 of it. Kill one first and it fizzles. | fuse 4 / 3 beats · rest 0.8 / 0.6 |

### Phases
Thirds, as the eye.

- **2 (66%):** "VOLUME UP!", its + flashes red, the meter of lights goes to two
  thirds, and pairing joins.
- **3 (33%):** "VOLUME MAX!", its lights red and it trembles. Every downbeat while
  it walks **thumps** 34 round its foot for **8**. Two handfuls of notes, and the
  drop's gap turns back the other way half way through.

### Glue
Mutes it: its lights go out, the beat stops, and a drop being built, a roll being
tipped, a shuffle being wound or a pairing being made is dropped ("MUTED"); it
rests 0.4s. Rings and notes already out carry on.

### Death
"DISCONNECTED". Its rings and notes go, its lights go out, and it comes apart in
blue, sky and ink with four rings (`src/wreck.lua`). Then the win card.

---

## 12. The Red Pen: GRAMMAR's encore (`redpen`)

**Files:** row `redpen` in `src/enemy.lua`, brain at `src/redpenboss.lua`, body at `src/redpen.lua`; the barrel's stand-ins are the row `penpart`
**Callout:** "PENS DOWN!" · **Body:** radius 13 round the nib and grip; the pen is 260 long, stood up it goes off the top of the screen.
**When:** Masters and PhD only, ten minutes after the Dictionary goes down.

### Entrance
Dropped onto the page (`arrive`) upright, tip in. Then it clicks itself ready --
out, in, out, three rising ticks over 0.65s -- and leans over to write, leaving a
first dot of ink. It writes for 0.8s before its first move.

### Ink
Everything it writes is red ink: **wet** (red) it hurts whoever crosses it, **dry**
(blush) it is only a mark, and at the end of its life it drops out a segment at a
time. The scrawl's line is wet 1.1s and hurts 6; a ring's 1.4s and 8; a grade
stroke's 1.4s and 12. A strike-through is never wet: a record, not a hazard.

### Idle
Writes at you: the line under its nib goes at you at **28 / 32 / 36** until 26
away, and the nib loops round it (7 out, 7 rad/s) -- a cursive scrawl that is ink.
A blot is lobbed at you every **2.6 / 2.3 / 2.0s** (8 on landing, a pool that hurts
5). It twiddles itself now and then (a full turn in its fingers) and clicks
nervously -- every few seconds, then constantly at phase 3. Cool between moves:
**2.0 / 1.6 / 1.25s** + up to 0.5s.

### Moves
Wrong weighs 1.4 under 140px (else 0.9). Strike-through 1.3 past 50px (else 0.7).
Shake 1.0. Grade, from phase 2, 1.1. The last move is ×0.2, the one before ×0.6.

| Move | Tell | Hot | Numbers |
| --- | --- | --- | --- |
| **Wrong** | A dotted ring round you that follows you while the pen lifts and is carried to its near side. | The nib runs round it, drawing a wet line. When it closes: **18** if you are inside, 40 to each of the crowd inside (never the last of their health), a red flash and a cross, "WRONG!". | aim 0.65 / 0.55 / 0.5 · radius 56 / 52 / 48 · lap 1.45 / 1.3 / 1.15s · rings 1 / 1 / 2 (the second 0.72 the size, aimed 0.8 as long) · rest 0.9 / 0.8 / 0.6 |
| **Strike-through** | It teeters back off its nib, a strip its own length (and 10 either side of its axis) dashed across the page through you -- following you for the first 60%, then locked, blinking and hatched, the pen rocking. | It falls flat, accelerating (about half a second): **22** under it, 30 to the crowd under it (never the last of their health) and they are thrown out sideways, a big knock, crumbs along its length and a red line left where it fell. It bounces, rattles and lies there -- the window. | tell 1.1 / 0.95 / 0.85 · lie 1.3 / 1.1 / 0.9 · rise 0.6 · falls 1 / 1 / 2 (the second's tell 0.7 as long) · rest 0.8 / 0.7 / 0.5 |
| **Roll** (phase 2+, inside a strike-through) | Half way through lying, the far edge of the ground it will cover is dashed in on your side. | It rolls 44 / 60 towards you at 52 (under your speed), the clip going round: **14** if it rolls over you, the crowd shoved along. | |
| **Shake** | It whips its top back and forth across the screen, wider and faster, shaking, specks off the nib. | Flicks a fan of blots round you, 30 to 120 out: **8** where one lands on you, then a pool (10 across, 4.5s, 6). | tell 0.85 / 0.75 / 0.65 · blots 5 / 7 / 9 · flicks 1 / 1 / 2 (0.5s apart, the second shifted half a gap) · rest 0.7 / 0.6 / 0.5 |
| **Grade** (phase 2+) | An F 100 tall and 62 wide over you, every stroke dashed in blush, the next one blinking red, the middle bar through you. | Written stroke by stroke at **300 / 330 / 360**, a hop between strokes: each stroke a wet band 4 wide (**12**). At phase 3 it then rings the F (a Wrong round the letter, not following you). | rear 1.15 / 1.05 / 0.95 · rest 1.0 / 0.9 / 0.7 |

### Phases
Thirds, as the eye.

- **2 (66%):** "RED INK!" -- the grade joins, and a strike-through rolls before it
  gets up.
- **3 (33%):** "SEE ME!" -- it clicks itself constantly, rings you twice, falls
  twice, flicks twice, and circles its F.

### Glue
Clicks it shut: the tip goes in, and a ring, a strike-through, a shake or a grade
being aimed or written is dropped ("CLICK!"), a ring left open and a letter left
unfinished; it rests 0.5s. A fall already going finishes, and a pen lying down
stays down until it is let go.

### Being hit
Its nib and grip are the body (radius 13, 20 on contact). The barrel is stood for
by 8 bodies 28 apart up it (`penpart`, radius 9) that every weapon finds and that
pass what they take to the pen; they never hurt anyone, and are off the page
outside the box. A hit on the barrel lights the pen in a blink of blush, at most
every 0.22s.

### Death
"OUT OF INK". Its stand-ins come off the page, the ink still wet dries, the tip goes
in and what was left in it runs out of the nib as a pool that hurts nobody; it comes
apart in red, blush and ink with three rings (`src/wreck.lua`). Then the win card.

## Iteration notes

These are observations from reading the code side by side, offered as things to
look at. None of them are bugs.

- **The Whistle is the odd one out.** It is the only boss with no phase-based
  escalation of its moves: its clocks are the same at 100% and at 10%. Only the
  pump marks progress. Every other boss gets shorter tells, more repetitions or a
  new move per third. A cheap fix would be phase lists on `blast.every`,
  `jacks.every` and `charge.every`.
- **Stamp and Dictionary are close siblings.** Their idle (hop numbers, a filler
  shot every 2.6s, cool times), their big move (slam/clap with the same rear,
  rest and splash ladders), their phase-2 "fill the area" move (audit/definition
  with rear 1.3, again 1.2 and a second pass in phase 3) and their weights all
  match. That is fine if intended, but the two fights may feel alike. The obvious
  places to tell them apart are the area moves and the filler shot.
- **Phase-2 unlocks get flat weights.** Audit (1.1) and definition (1.0) ignore
  distance, while the moves they join are distance-weighted. The Eye's sink and
  weep, and the Metronome's scale, react to how far away you are.
- **The Still Life picks uniformly.** It does not react to your distance or
  movement at all, apart from the table lift. That is coherent with "still", but
  it is the only boss whose choices you cannot influence.
- **Glue strength varies a lot.** On the Die it is a guaranteed fumble if timed
  during the tumble (×1.5 damage for 3s on the d20). On the Still Life it does
  little once pieces are out. On the Eye and the Metronome it cancels the
  current tell. The gap is worth a look if glue builds turn out dominant on
  MATHS.
- **Tell lengths cluster at about 0.5–1.3s** everywhere except the Metronome,
  whose count-ins are 2.4–4s. That is by design, since the beat is the tell, but
  it makes MUSIC the most readable and slowest fight.
- **Fight-length check:** cycle-1 health is 1260 everywhere, and a strong build
  deals about 30 DPS into a single target. The Die's fumble and the Still Life's
  extra hittable pieces both shorten their fights relative to the others.
