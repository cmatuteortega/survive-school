# Boss ideas: a second boss for every lesson

Each lesson already ends on a boss of its own (`boss` on its row in
`src/subjects.lua`). These are ideas for a **second** one per lesson, to be
fought after or instead of the first depending on the course rung
(`Course.list` in `src/course.lua`). Each one is different from the boss its
lesson already has, and each names the version of the 3D method
(`3dmethod.md`) that suits it.

The Atom is built (`src/atom.lua`, `src/atomboss.lua`; see `BOSSES.md`). It
walks on ten minutes after the eye goes down at a master's and a doctorate, which
is how every second boss here is meant to arrive: named as the lesson's `encore`
in `src/subjects.lua`, sent by the courses whose `bosses` is 2 in
`src/course.lua`. The Piggy Bank is built the same way (`src/piggy.lua`,
`src/piggyboss.lua`), and so are the Tesseract (`src/tesseract.lua`,
`src/tesseractboss.lua`) and, for MUSIC, the Speaker (`src/speaker.lua`,
`src/speakerboss.lua`) -- built in place of the Gramophone below. The rest are
still ideas only.

| Lesson | Current boss | Second boss | Drawn as |
|---|---|---|---|
| SCIENCE | eye | **The Atom** (built) | painted live |
| P.E. | whistle | **The Vaulting Box** | baked poses |
| GRAMMAR | dictionary | **The Typewriter** | baked + live part |
| FINANCE | stamp | **The Piggy Bank** (built) | painted live |
| MUSIC | metronome | **The Speaker** (built; was the Gramophone) | painted live |
| MATHS | die | **The Tesseract** (built) | lines, projected live |
| ART | still life | **The Mannequin** | painted live under the lamp |

## SCIENCE: The Atom (built)

- **Drawn:** the nucleus is a painted sphere, as the eye is (`src/eyeball.lua`).
  The electrons go round it on tilted rings, drawn in front of or behind the
  nucleus depending on where they are in the orbit.
- **Fight:**
  - The orbits sweep through the box, and the rings tilt between attacks. A
    ring seen edge-on is a line; a ring seen face-on is a circle.
  - It throws off an electron that chases you.
  - Below half health it **splits in two** (fission), and each half has fewer
    rings.

## P.E.: The Vaulting Box

- **Drawn:** the stacked wooden gym box, baked as one picture per number of
  layers (5 down to 1), the way the stamp is baked in poses.
- **Fight:**
  - Its shadow on the page warns where it will land, then it slams down.
  - Each time it lands, a layer flies off and slides across the box as a
    hurdle wall.
  - With fewer layers it gets lighter and faster. The last cushioned top hops
    frantically.

## GRAMMAR: The Typewriter

- **Drawn:** a baked body. The typebars striking are poses, and the carriage is
  drawn live, the way the metronome's pendulum is.
- **Fight:**
  - It types letters along a ruled line, left to right, as a creeping wall of
    hazards.
  - **Ding:** the carriage return slams back and sweeps that row.
  - **Backspace** erases your pen strokes.
  - **CAPS LOCK** turns the next wave into big versions of the enemies.

## FINANCE: The Piggy Bank (built)

- **Drawn:** a painted ellipsoid, the eye's method stretched. Cracks spread
  across it as it takes damage, the way the eye's veins do. (Built as nine
  ellipsoids -- barrel, snout, ears, legs, tail -- seen from a little above, so it
  can turn to face where it is going.)
- **Fight:**
  - It trots and charges.
  - It drops coins out of its slot. They really are pickups, but they're laid
    out as bait in its charge lanes, so you trade greed against safety.
  - At low health it shatters, and coins burst out as a bullet ring. Survive it
    and you collect them.
  - (Added when built) **Savings:** coins left lying are called back into its
    slot all at once, and hurt on the way -- so leaving the money is its own
    risk.

## MUSIC: The Gramophone

- **Drawn:** a baked body whose horn turns to aim at you, so its heading
  matters. The record is drawn spinning live.
- **Fight:**
  - It blasts sound in a cone from the horn.
  - Notes spiral off the record.
  - **The needle skips:** it repeats its last attack two or three times, and the
    repeats get out of sync. A sibling of the metronome's beat, but about
    stuttering rather than keeping time.

## MUSIC: The Speaker (built)

Built instead of the Gramophone: a cylindrical bluetooth speaker.

- **Drawn:** a cylinder painted live the piggy bank's way (a side and two flat
  caps), in a frame that can tip over and roll. Ribbed knit, a big + and -, a
  ring of lights round its top and a radiator that pumps on the beat. It squashes
  and stretches.
- **Fight:** about volume rather than time.
  - **The drop:** a bar of build, then rings of bass across the whole box, one a
    beat, each with a quiet gap that steps round it: you dance round it.
  - **The roll:** it tips over and rolls down a lane, off the walls.
  - **The shuffle:** notes that bounce round the box.
  - **Pairing:** it pairs with the nearest of the crowd, which all go off
    together on the beat.
  - Glue mutes it.

## MATHS: The Tesseract (built)

- **Drawn:** a 4D cube spun live and projected onto the page. Its faces are
  painted like the die's (`src/dice.lua`), or it can simply be drawn as lines,
  which `pixelart.line` allows at any angle. (Built as lines: the far edges
  slate, the near ones ink, and the struts along w red. The inner cube is
  dithered blush as a heart, and the silhouette is the hull of the sixteen
  corners.)
- **Fight:**
  - **Inside-out:** the inner cube becomes the outer one, and anything caught
    between the two gets crushed or flung. (Built as two squares on the floor,
    turned the way the cube is turned. The band between them goes off and the
    crowd in it is flung out. From the second phase it turns back straight
    after, and the middle and a rim go off instead.)
  - **Unfold:** it lays itself out on the squared paper as a net of cubes, and
    the net's squares go dangerous in sequence. (Built as Dali's cross of eight,
    numbered: root to tip, then tip to root, then shuffled.)
  - (Added when built) **Corners:** its corners blink and fly straight out the
    way they stick out on the page, the far ones fast and the near ones slow.
  - (Added when built) **Through the fourth dimension:** from the second phase,
    when you are far off, it turns out of the page and back in where you were
    standing, with a square shock.

## ART: The Mannequin

- **Drawn:** the wooden artist's figure, made of spheres and cylinders painted
  live and lit by the still life's moving lamp (`src/plaster.lua`).
- **Fight:** a life-drawing class played like Grandmother's Footsteps.
  - It strikes a pose and freezes. While it holds still, the horde freezes too.
  - When it moves, everything lunges, and the shadow its pose throws does
    damage.
  - The still life is about light on objects that don't move; this one is about
    holding still.

## Build order

The cheapest to build, because each is mostly an existing body with a new brain:

- The Atom reuses the eye's sphere painter.
- The Piggy Bank reuses the same painter, stretched into an ellipsoid (built).
- The Mannequin reuses the still life's lamp.

The Typewriter would be the most new work. (The Tesseract, built, turned out
cheaper than expected: drawn as lines it needs no painter at all.)
