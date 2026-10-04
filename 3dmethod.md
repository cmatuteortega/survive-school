# The 3D method

How the P.E. whistle boss was made to look solid, and how to do the same for
another character. The working example is `art/whistle.py`, which writes the
`BAKE:whistle` block in `src/sprites.lua`; the game side is `turns` on its row in
`src/enemy.lua`.

The short version: **model the thing in 3D in a script, ray-trace it at sprite
size straight into palette letters, do that once per heading, and bake the
results into `src/sprites.lua` as ordinary ASCII sprites.** The game never knows
anything was 3D. It draws pixel art like it always has, picking one of a ring of
pictures.

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

1. **Copy `art/whistle.py`** to `art/<name>.py`. Replace the `sd_*` functions and
   `model()` with the new shapes, set the pivot to the bulk of the body, and pick
   materials and ramps. (Once there are two of these scripts, the tracer, ramps,
   lines and baking should move into a shared `art/raytrace.py`, with each
   character's file holding only its model. One script didn't justify it yet.)
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

## Where it fits and where it doesn't

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
