# Boss ideas: a second boss for every lesson

Each lesson already ends on a boss of its own (`boss` on its row in
`src/subjects.lua`). These are ideas for a **second** one per lesson, to be
fought after or instead of the first depending on the course rung
(`Course.list` in `src/course.lua`). Each one is different from the boss its
lesson already has, and each names the version of the 3D method
(`3dmethod.md`) that suits it.

None of this is built. These are ideas only.

| Lesson | Current boss | Second boss | Drawn as |
|---|---|---|---|
| SCIENCE | eye | **The Atom** | painted live |
| P.E. | whistle | **The Vaulting Box** | baked poses |
| GRAMMAR | dictionary | **The Typewriter** | baked + live part |
| FINANCE | stamp | **The Piggy Bank** | painted live |
| MUSIC | metronome | **The Gramophone** | baked + live part |
| MATHS | die | **The Tesseract** | painted live |
| ART | still life | **The Mannequin** | painted live under the lamp |

## SCIENCE: The Atom

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

## FINANCE: The Piggy Bank

- **Drawn:** a painted ellipsoid, the eye's method stretched. Cracks spread
  across it as it takes damage, the way the eye's veins do.
- **Fight:**
  - It trots and charges.
  - It drops coins out of its slot. They really are pickups, but they're laid
    out as bait in its charge lanes, so you trade greed against safety.
  - At low health it shatters, and coins burst out as a bullet ring. Survive it
    and you collect them.

## MUSIC: The Gramophone

- **Drawn:** a baked body whose horn turns to aim at you, so its heading
  matters. The record is drawn spinning live.
- **Fight:**
  - It blasts sound in a cone from the horn.
  - Notes spiral off the record.
  - **The needle skips:** it repeats its last attack two or three times, and the
    repeats get out of sync. A sibling of the metronome's beat, but about
    stuttering rather than keeping time.

## MATHS: The Tesseract

- **Drawn:** a 4D cube spun live and projected onto the page. Its faces are
  painted like the die's (`src/dice.lua`), or it can simply be drawn as lines,
  which `pixelart.line` allows at any angle.
- **Fight:**
  - **Inside-out:** the inner cube becomes the outer one, and anything caught
    between the two gets crushed or flung.
  - **Unfold:** it lays itself out on the squared paper as a net of cubes, and
    the net's squares go dangerous in sequence.

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
- The Piggy Bank reuses the same painter, stretched into an ellipsoid.
- The Mannequin reuses the still life's lamp.

The Tesseract and the Typewriter would be the most new work.
