# The 3D method

How the P.E. whistle boss was made to look solid, how that compares with the
eye boss's painted sphere, and how to do either for another character. The working example is `art/whistle.py`, which writes the
`BAKE:whistle` block in `src/sprites.lua`; the game side is `turns` on its row in
`src/enemy.lua`. The tracer itself -- everything that is not the model -- is
`art/raytrace.py`, shared with the MUSIC metronome (`art/metronome.py`), which is
also the example of a baked body with a part drawn live on top of it (see **A
moving part on a baked body**), and the FINANCE stamp (`art/stamp.py`), the example
of a body baked in several poses so it can animate (see **Poses: a body that
moves**), and the GRAMMAR dictionary (`art/dictionary.py`), poses again, one of them
a part hinged off the body and one built about a different point (see **Poses with
a hinge: the dictionary**).

The short version: **model the thing in 3D in a script, ray-trace it at sprite
size straight into palette letters, do that once per heading, and bake the
results into `src/sprites.lua` as ordinary ASCII sprites.** The game never knows
anything was 3D. It draws pixel art like it always has, picking one of a ring of
pictures.

## Two ways to be solid

The game has six bosses drawn as solid objects, made in two different ways --
the metronome is the whistle's way with one part done the eye's, the stamp and
the dictionary are the whistle's way with more than one picture per heading, and the MATHS die is
the eye's way on flat faces (see **Painted live on flat faces: the die**).
Pick the one that fits the character before starting.

| | **Baked views** (the whistle) | **Painted live** (the eye) |
| --- | --- | --- |
| where | `art/whistle.py` → `BAKE:whistle` in `src/sprites.lua` | `src/eyeball.lua`, every frame |
| what it can show | any shape you can model: boxes, tubes, rings, cut-outs | shapes with a formula you can solve per pixel: a sphere, an ellipsoid |
| turning | one of N headings (16), stepped through | any angle at all, in 3D, including up and down |
| changing over time | no: each view is a fixed picture | yes: blinks, squash and stretch, veins creeping in with damage, a roll that turns the surface |
| cost | nothing at runtime; ASCII in `sprites.lua` | a few thousand pixel tests a frame for one body |
| looks like the other sprites | yes: it *is* a sprite | close: same palette and ink rim, but drawn as runs |

The eye's way works like this. For every pixel inside the outline it works out
the point on the sphere under it, turns that point into the ball's own frame,
and asks what is painted there: iris, pupil, vein or white. The light is fixed
on the screen and the ball turns underneath it. That's why an iris looking off
to the side goes thin and oval, and why the veins come round with a roll. Read
the header of `src/eyeball.lua` for the full account.

**Use baked views** when the shape is complicated (anything you'd build from
several parts) and its look doesn't change during a fight. Turning to face the
player is the only movement it needs.

**Paint live** when the body is one simple round shape and its surface has to
move: an eye that rolls, blinks or swells, or a ball whose markings turn with it.

**Don't redo the eye with baked views.** It was already given the live
treatment (merged from main after this method was written), and baking would be
a step back: 16 fixed headings can't roll, blink, squash or go bloodshot. The
live method is also the reference for how its lighting is chosen. Both methods
use a light from the top left and in front, fixed in the room or on the screen,
so the two bosses look lit by the same window.

## Why it fits the rendering rules

The four rules in `CLAUDE.md` look like they rule this out. They don't, because
everything 3D happens before the game runs:

- **Eight colours, no alpha.** Each pixel is traced once, at its centre, and its
  shade is *chosen* from a ramp of palette letters rather than blended. There is
  no anti-aliasing, so no ninth colour can appear.
- **Whole pixels, never at an angle.** Nothing is rotated at draw time. Every
  heading is its own baked picture, the same way `pixelart.turn` bakes the
  rocket's eight. These are just rendered rather than turned, because turning a
  drawing of a solid thing gives you a drawing of it lying on its side.
- **Art is ASCII.** The output *is* rows of palette letters. They go through
  `pixelart.newSprite` like every other sprite, and off-palette art still asserts
  at load.
- **The canvas** is untouched. These are sprites like any other.

## The pipeline

### 1. Model it with signed distance functions

Each part is a small function giving the distance from a point to that shape's
surface: negative inside, positive outside. The whistle is three of them:

| part | shape | function |
| --- | --- | --- |
| barrel | cylinder, rims rounded | `sd_barrel` |
| mouthpiece | rounded box, thicker towards the barrel | `sd_tube` |
| lanyard ring | torus | `sd_ring` |

You combine them with `min` (union), `max(a, -b)` (cut b out of a, which is how
the window slot is made) and `max` (intersection). Rounded edges are free: take
the radius off the box and subtract it back from the distance. Rounded edges
matter here, because they're what produce the strip of highlight along an edge,
and that strip is most of what reads as "solid" at this size.

Work in made-up units at roughly one unit per pixel. The whistle's barrel has a
radius of 11.5 and is drawn at 0.92 units per pixel.

Give each part a **material name** (`'body'`, `'ring'`) by having the scene
return the distance and the name of whichever part is nearest. The material
decides which colour ramp it gets.

### 2. Stand it in a room and turn it

There are three spaces, and keeping them apart is what makes turning work:

- **Model space** is whatever was convenient to build in. The whistle's
  mouthpiece points along −x.
- **Room space** is the page: x right, y up off the paper, z towards the viewer
  (down the screen). A heading `h` turns the model about its **pivot** so that
  its front points along `(cos h, sin h)` on the page. That's the same angle
  `math.atan2(dy, dx)` gives in the game, so the game picks a view with no
  conversion.
- **Camera space** is the room tilted by `PITCH` (34° for the whistle), so you
  look down at the page at an angle and see a top as well as a side. The camera
  is orthographic, so there's no vanishing point and everything stays the size
  it is.

**The light lives in room space**, not on the model. That's why the whistle is
lit from the top left whichever way it points. Put the light on the model and
the shading would spin round with it.

**The pivot is the point that stays still while it turns.** For the whistle
that's the barrel's middle, because the barrel is the body: it's where the hit
circle is and what the shadow sits under. Pick the bulk of the thing, not the
middle of its bounding box.

### 3. Trace one ray per pixel

For each pixel, march a ray from the camera: step forward by the scene's
distance, which is always a safe step, until the distance is tiny (a hit) or the
ray has gone too far (empty, `.`). Then:

- **Normal** is the gradient of the scene's distance at the hit point (finite
  differences, six samples).
- **Diffuse light** is `dot(normal, LIGHT)`, multiplied by 0.35 if a second ray
  towards the light hits something (a shadow).
- **Specular** uses the half-vector to the camera, raised to the 40th power, for
  the glint.

### 4. Snap the light to a palette ramp

This step makes it look like pixel art rather than a render. The whistle's
red ramp:

| condition | letter | colour |
| --- | --- | --- |
| specular > 0.6 | `w` | paper (the glint) |
| diffuse > 0.78 | `k` | blush (lit) |
| diffuse > 0.2 | `r` | red (middle) |
| facing down and diffuse > 0.02 | `r` | red (light bounced off the page) |
| otherwise | `s` | slate (shadow) |

The other ramps the palette gives you:

| body colour | glint | lit | middle | shadow |
| --- | --- | --- | --- | --- |
| red | `w` | `k` blush | `r` red | `s` slate |
| blue | `w` | `c` sky | `b` blue | `s` slate |
| grey / metal | `w` | `w` paper | `g` graphite | `s` slate |

Ink (`o`) is kept for lines, never used as a shade (see step 5). Some materials
deliberately get fewer steps: the lanyard ring uses three, because it's small
and a fourth step would just be noise.

**The bounce-light row is not optional.** Without it the shadow side is one flat
slate shape, and at sprite size that reads as a hole cut in the body. A strip of
mid colour where the surface faces the page brings it back as a side.

### 5. Draw the lines

Two passes after tracing, and both matter as much as the shading:

- **Silhouette:** any filled pixel next to an empty one becomes ink (`o`). Every
  sprite in the game has a dark rim, and this one has to as well or it floats.
- **Creases:** where two neighbouring pixels of the same material have normals
  that disagree sharply (dot product below 0.55), the lit or middle pixel steps
  down to slate. That's what draws the edge where the barrel's flat face turns
  into its curved side. Without it the planes merge into one blob.

Details that are *holes* (the window slot, the mouth of the tube) are tested in
model space at the hit point and painted ink directly.

### 6. Every heading in one box

Render each of the `VIEWS` headings (16 for the whistle, one every 22.5°) into
the same square, centred on the pivot. Then crop all of them to **one shared
box**: the union of what every view covers, kept symmetric left to right about
the pivot. The origin (`ox`, `oy`) is where the pivot landed in that box.

That one rule is what makes turning look like turning: the game swaps pictures
and the pivot never moves. It also means the hit circle, the shadow and
everything else the game measures off the origin stay put.

### 7. Bake

`python3 art/whistle.py --bake` writes everything between two marker comments
in `src/sprites.lua`:

```lua
    -- BAKE:whistle begin
    Sprites.WHISTLE = {
        ox = 31, oy = 26,
        { -- heading 0/16
            "....",
        },
        ...
    }
    -- BAKE:whistle end
```

`Sprites.load` compiles each into `Sprites.whistleViews[k]` with the shared
origin, and puts the first one in `Sprites.enemies` so anything asking for the
row's ordinary sprite still gets a whistle. As with `art/bake.lua`, art travels
one way: the script is the drawing board, `sprites.lua` is the game, and nothing
reads `art/` at runtime.

## The game side

One field on the enemy's row does it: `turns = "whistleViews"`, naming the list
of views on `Sprites`.

- `Enemy:update` works out which view points at the player (heading divided by
  a sixteenth of a turn, rounded) and steps `view` towards it one view at a time,
  the short way round, every `TURN_STEP` seconds. Stepping rather than snapping
  is what makes it look like it turns; at 0.02s a step, half a turn takes about a
  third of a second.
- `Enemy:footing` hands that view to both the body and the blank stamped under
  it, so the overprint cut-out always matches the picture.
- Glued, it stops turning: a thing stuck to the page is stuck the way it was
  pointing.

Any row with `turns` gets this. Nothing else in the game needs to know.

## Doing another character

1. **Copy `art/whistle.py`** to `art/<name>.py`. Replace the `sd_*` functions,
   `model()` and `shade()` with the new shapes and ramps, set the pivot to the
   bulk of the body, and hand them to `Rig`. The tracer, the red ramp (the
   default whenever `shade` answers nothing), the lines, the shared box and the
   writing between markers are all `art/raytrace.py`; a character's file holds
   only its model. Splitting it out changed nothing: the whistle re-bakes to the
   same bytes.
2. **Add markers** `-- BAKE:<name> begin` / `end` in `Sprites.load`, plus the loop
   that compiles the views with the shared origin.
3. **Preview before baking.** Render all views into one image, upscaled with
   nearest-neighbour, on a sample of ruling. Judge it there, not in ASCII and not
   at one heading. This was the loop for the whistle; a dozen iterations is
   normal.
4. **Set `turns`** on the row and a `radius` that matches the bulk around the
   pivot, not the whole silhouette.
5. **Check it in-game** with something walking a circle round it. For a boss, the
   title's dev BOSS button gets you straight to the fight.

## What was learned on the whistle

- **Don't render faces in 3D.** The first version painted the eyes onto the
  barrel in 3D, and at sprite size perspective chewed them into something nobody
  could read. Anything that has to *read* (eyes, a mouth, a symbol) should be
  authored flat and stamped on where the surface projects. The whistle
  eventually dropped its face altogether.
- **A small angle beats a dramatic one.** A strong tilt made the mouthpiece
  stretch away up the screen. 34° downwards in the room shows the top without
  distorting the length.
- **Front-ish light.** Light from the side left half the body in slate. Light
  from top left *and* towards the viewer keeps most of what you see lit, with the
  shadow as a band down one side.
- **Edge-on views are thin, and that's true.** Pointing straight at you or away,
  you're looking along a narrow object. That's honest, but a squat character
  turns better than a long one.
- **One sample a pixel, always.** It's tempting to supersample for smoother
  edges, but averaging is exactly what invents colours the palette doesn't have.
  Smoothness comes from rounding the model's edges instead.

## A moving part on a baked body

The metronome's pendulum swings, and a baked view is a fixed picture: sixteen
headings times every angle of swing is not a budget, and stepping between swing
angles would read as a flicker. So the body is baked and the arm is not. The
bake writes two extra lines beside the views:

```lua
    Sprites.METRONOME = {
        ox = 18, oy = 22,
        arm = { x = -8.787, y = -7.500, z = 0.000, lean = 0.1806, len = 38.0, bob = 0.62 },
        cam = { pitch = 0.59341, unit = 0.920, bias = 0.6087 },
        ...
```

`arm` is where the arm hangs, in model units relative to the pivot; `cam` is the
camera's tilt, the size of a pixel, and `bias`, which is where the pivot's own
pixel sits (`half / unit - piv` in `Rig.bake`). `Metronome.armPoint` runs the same
sums as the trace in reverse -- model to room by the view's heading, room to
camera by the tilt, camera to pixels -- and gets a point on the arm in pixels
from the sprite's origin. The arm is then plotted with `pixelart.line`, which
goes down at any angle because it is plotted, not a sprite.

Three things make it sit on the body rather than float over it:

- **It uses the heading of the view being shown, not the true one.** The body
  is quantised to sixteen; an arm turned to the exact angle would slide across
  the panel between steps.
- **Painter's order by view.** When the panel faces away from the camera the arm
  is drawn first and the body covers it, so from behind only the tip shows over
  the cap; otherwise it is drawn after (`Metronome.armInFront`). A per-pixel
  depth test was not needed for one thin rod.
- **The preview draws it too.** `python3 art/metronome.py --preview out.png` puts
  every view on the MUSIC page with the arm swung, using the same sums, so the
  pivot can be placed on the panel before anything is baked.

The same split would serve any boss with one moving part: a wheel, a lid, a
needle. Bake what turns, plot what moves, and bake the numbers the plot needs.

## Poses: a body that moves

The stamp does not have a part that moves; the *whole thing* moves. It rocks back
on its heel before it jumps, pitches forward as it comes down and flattens when it
lands. None of that can be plotted on top of a picture, and none of it is a turn,
so the answer is more pictures: each **pose** is the model bent into that shape and
traced at every heading, a ring of its own.

```
stand    upright                          (at rest, and in the air)
rear     rotated 20° about the back edge  (the wind-up: front off the page)
lean     rotated 20° about the front edge (coming down: face first)
squash   scaled 1.12 across, 0.68 up      (the impact)
```

How `art/stamp.py` does it:

- **A pose is a function from the posed body back to the upright one.** `rear(p)`
  rotates a point the other way about the heel and hands it to the ordinary
  `model()`; `squash(p)` divides by the scale. The tracer marches the posed distance,
  so the pose wraps the model rather than being built into it, and `shade()` is asked
  about the *unposed* point, so the label stays on the label however the body leans.
  A non-uniform scale is not an exact distance any more, so the distance is
  multiplied by the smaller scale, which keeps every step of the march safe.
- **Pose about the floor.** Each pose pivots on a point on the page -- the heel,
  the toe, the middle of the pad -- so no pose lifts the body off its shadow. Lifting
  is the game's job (`hop`, `Enemy:footing`), and a pose that lifted too would be
  two answers to one question.
- **One box for every pose.** `raytrace.share` crops every frame of every pose to
  the union of all of them, symmetric about the pivot, with one origin. Swapping
  `stand` for `rear` mid-air is then as still as swapping one heading for the next:
  the pivot never moves. It does mean the bottom of the box is the bottom of the
  lowest pose, not the foot, which is why the row carries `ground` for its shadow.
- **Spend the symmetry.** The stamp is the same front and back, so heading *k* and
  heading *k + 8* of an upright pose are the same picture, and leaning forward at
  one heading is rearing back at the opposite one. So stand and squash are traced at
  eight headings, rear at sixteen and lean not at all: sixty-four pictures in play
  from thirty-two on disk, the rings put together in `Sprites.load`. A model without
  that symmetry would bake all four rings in full.
- **Bake what the game needs to line up.** The stamp's pad has to land in a ledger
  cell, so the model is sized from the page (40px across is `40 * S` units; 12px down
  the screen is a floor depth of `12 * S / sin(PITCH)` -- the floor is foreshortened by
  the *sine* of the tilt and height by its *cosine*), and the bake writes `foot`, the
  pixels from the origin down to the middle of the pad, for the brain to seat it by.
- **Preview every pose.** `python3 art/stamp.py --preview out.png` draws the four
  rings as the game builds them, on the ledger, with the cell the pad should cover
  outlined under each. That outline is how the floor maths above was caught being
  wrong the first time.

The game side is one field more than `turns`: `poses = "stampPoses"` on the row,
and the brain setting `e.pose` to a ring's name. `Enemy:footing` picks
`Sprites[poses][pose][view]`, and the blank under it follows, so nothing else knows
the body has more than one shape.

Budget: a pose is a ring of views, so it costs what a second boss would. Thirty-two
51x46 pictures are about 1,600 lines of `sprites.lua`. Pick poses that are held long
enough to be seen -- a tell, a fall, an impact -- rather than in-betweens: at this
size the eye fills the gap between two held poses by itself.

## Poses with a hinge: the dictionary

The GRAMMAR boss is a fat dictionary lying on the page, and it is the stamp's method
with two things the stamp did not need. Its poses are `shut`, `ajar` (the front board
lifted off the pages, a mouth) and `open` (on its back, both leaves flat).

- **A hinge is a pose of one part.** The stamp's poses bend the whole body; the
  dictionary's `ajar` turns only the upper board, about the line where it meets the
  spine. `shut_model(p, lift)` takes the point into the board's own frame for that
  one part (`lifted`) and leaves the rest of the model alone, so the pages and the
  spine are traced exactly as they were. The material is decided off the *board's*
  point as well: its underside is the endpaper, so a lifted board shows a white mouth,
  and it is lit whichever way it faces, because a slate inside reads as a hole.
- **A pose can be a different model.** Open is not the shut book bent: it is its
  own model, built about the spine, with the pages rising out of the gutter as a
  height field (`page_top`; a height field's distance is not exact, so it is scaled
  down by the slope's worst case to keep the march safe). Built about the spine
  because the spine is the middle of the move the game plays on it, so swapping shut
  for open shifts the picture half a book -- which is fine, because it only ever
  happens on a landing, where nobody is looking for it.
- **Ask the model, not the normal.** `shade` is handed the room's normal, which turns
  with the heading. "Is this the fore-edge?" has to be asked of the point in the
  model (its x), never of the normal's x; only the normal's y, which no heading
  changes, is safe to read. The first preview had no thumb index for that reason.
- **Spend the symmetry where there is some.** Shut and ajar have the spine on one
  side, so they are baked at all sixteen headings. An open book is the same either
  way round, so it is baked at eight and repeated: forty pictures, about 2,400 lines
  of `sprites.lua`.

`python3 art/dictionary.py --preview out.png` draws the three rings on the GRAMMAR
page with the floor under the pivot marked, which is where `foot` is checked. The
brain (`src/dictionary.lua`) lines the open book's spine up with the paired ruling
off that number.

## Painted live on flat faces: the die

The MATHS boss (`src/dice.lua`) is a d6, then a d10, then a d20, and it is the eye's
method rather than the whistle's, for a reason worth keeping in mind for any future
character: **a die has no front.** Baked views pay for headings -- sixteen pictures
of a thing turning to face you -- and what a die needs is to tumble end over end in
any direction and come to rest on any face. Baking that would be a picture for every
orientation, which is not a budget; painting it fresh each frame costs about what
the eye does.

A convex solid is also the easiest thing there is to paint this way. Each die is a
list of face planes, `n . p <= h` in its own frame, and that list is the whole
model: corners, and the box a frame is painted in, are found by intersecting every
triple of planes at load. For each pixel the ray along the view is cut by every
plane: a plane facing the camera bounds the depth from above, one facing away from
below, and the pixel is on the die if the nearest upper bound is above the furthest
lower one -- the face that gave the nearest bound is the face it is on. Twenty
planes, a couple of thousand pixels.

What changes from the sphere:

- **One colour per face.** A face is flat, so its light off its screen normal is one
  number and it is one step of the ramp (blush, red, a checker, slate). No banding,
  and the die turning is faces trading places on the ramp -- the thing flat
  shading is best at in eight colours.
- **Edges from the face buffer.** The raster keeps which face each pixel is on; a
  pixel whose right or lower neighbour is another face is ink. One pixel wide and
  exact, with no edge list to project.
- **The room is tilted**, `PITCH` 0.6, the whistle's angle, so a die at rest shows
  its top square-ish to the light and a side or two.
- **What reads is still kept flat.** Pips are round and survive foreshortening, so
  they are painted in 3D: the pixel goes back into the die's frame and is tested
  against the face's pip layout. Numbers are not, so the d10 and d20 stamp the 3x5
  font flat over the middle of the face on *top*. On top, not most towards the
  camera: in a tilted room those are often different faces, and the stamped number
  has to be the number rolled.
- **Motion is the body's.** `Dice:roll` turns it about the floor line square to its
  travel at the rate that rolls it without sliding; `Dice:settle` tips the nearest
  face flat, or a named one (the glue's loaded die). The brain only pushes.

To make another convex thing this way, add a face list to `Dice.solids` (unit
normals, one `h`, labels) and the rest follows. Anything with a hole or a dent is
not convex and is back to the whistle's tracer.

## Smaller than a boss: the teardrop

The live method also works at five pixels across, for things whose *heading* is
the point. The eye's fan and its tears (`src/teardrop.lua`) are a ball with a
cone tangent to it, painted per pixel along whichever way the drop is moving on
the screen -- including the climb and fall of a thrown tear, which is what makes
its parabola read as one. At that size the ramp has room for two fills, one
glint pixel and the ink outline, and that is enough: what sells it is the shape
pointing the way it goes, not the shading. It costs one small box of pixel tests
per drop, which is fine for the few dozen a boss throws.

## Where it fits and where it doesn't

- **Convex and tumbling:** a die, a block, a crystal -- anything flat-faced that has
  to turn every way rather than face you -- is a face list painted live (the die),
  not baked.
- **Good fits:** bosses and anything else big (the whistle is 63 by 41 pixels
  per view), and objects whose heading matters, such as something that aims, or
  a weapon that should point the way it's going.
- **Poor fits:** the ordinary horde. A blob is eight pixels across, and at that
  size the ramp has room for about two shades, so a hand-drawn doodle reads
  better. The horde is also reskinned per lesson by hand
  (`Sprites.enemySkins`), and a rendered enemy would need every skin rendered
  too.
- **Not at all:** anything the player draws: the hero, the sword, the star and
  the rest of the drawn designs. Those are the player's own pixels.
- **Budget:** each view is a block of ASCII in `sprites.lua`. Sixteen views of a
  63-wide sprite is about 700 lines, which is fine for a boss. Eight views is
  plenty for something that turns less often or is smaller.
