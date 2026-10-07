# The 3D method

How the bosses that are drawn as solid objects are made to look solid, and how to
do the same for another character.

There are two ways here, and both paint the body fresh, a pixel at a time, for
whatever way it is facing and whatever it is doing:

- **Built of simple solids** (`src/solid.lua`): the P.E. whistle, the MUSIC
  metronome, the FINANCE stamp, the GRAMMAR dictionary and ART's marble. Each is a
  row in `src/solids.lua` -- a list of boxes, cones, cylinders and ellipsoids, and
  the colours to paint them -- and one shared tracer turns that into a picture.
  See **Built of simple solids**.
- **Painted live by a painter of its own**: the eye (`src/eyeball.lua`), the
  MATHS die (`src/dice.lua`), the ART still life (`src/plaster.lua`), SCIENCE's
  atom (`src/atom.lua`), FINANCE's piggy bank (`src/piggy.lua`), MUSIC's speaker
  (`src/speaker.lua`), GRAMMAR's red pen (`src/redpen.lua`) and P.E.'s deodorant
  (`src/deodorant.lua`), each with a method of its own for the one thing it does
  that nothing else does. The MATHS tesseract (`src/tesseract.lua`) is neither: a
  solid in four dimensions, projected every frame and drawn as lines (see
  **Projected live as lines: the tesseract**).

**The first five used to be baked.** They were modelled as signed distance fields in
Python (`art/raytrace.py` and a script each), ray-marched ahead of time into rings
of ASCII views -- sixteen headings, and a ring per pose for the ones that move -- and
written into `src/sprites.lua`. That bought any shape a distance field could
describe, and cost a turn in sixteenths, a pose as a held picture with nothing
between it and the next, and seven thousand lines of `sprites.lua`. They were moved
onto the piggy bank's method once there were enough live bodies to show it was
affordable; the same models, the same sizes in the same units, the same colours,
rebuilt out of solids a ray has a closed answer for. **Built of simple solids** is
how; the sections after it on the metronome, the stamp, the dictionary and the
marble are what each of them does with being live.

## Why it fits the rendering rules

The four rules in `CLAUDE.md` look like they rule this out. They don't:

- **Eight colours, no alpha.** Each pixel is traced once, at its centre, and its
  shade is *chosen* from a ramp of palette colours rather than blended. There is
  no anti-aliasing, so no ninth colour can appear.
- **Whole pixels, never at an angle.** Nothing is rotated at draw time. A body is
  painted fresh for the heading it faces, the way `pixelart.turn` bakes the
  rocket's eight up front -- it is just rendered rather than turned, because a
  turned drawing of a solid thing is a drawing of it lying on its side -- and it
  comes out as rows of whole-pixel runs.
- **Art is ASCII.** The solids are numbers, not art; what they come out as is
  palette keys (`w`, `k`, `r`, `s` and the rest), the same letters a sprite is
  written in, put through `Palette.key`.
- **The canvas** is untouched.

## Built of simple solids

`src/solid.lua` is the tracer and `src/solids.lua` the five models. The game asks a
body for nothing a painted body does not already answer: `draw(x, y)`,
`drawMask(x, y, pad)`, `shadowScale` and an optional `ground` (`Enemy:draw`). A row
says `solid = "whistle"` and `Enemy.new` makes the body; `Enemy:update` turns it
towards you and hands it whatever pose the brain has put it in.

### The camera

The bake's camera, to the digit, so the five came out of the move the size and the
colour they always were:

- **Room space** is the page: x right, y up off the paper, z towards the viewer
  (down the screen). A heading `h` turns the model about its **pivot** so that its
  front (model −x) points along `(cos h, sin h)` on the page -- the angle
  `math.atan2(dy, dx)` gives in the game, so a body faces you with no conversion.
- **The camera** is the room tilted by `PITCH` (34°), so you look down at the page
  at an angle and see a top as well as a side; orthographic, so nothing changes size
  with distance. One pixel is `UNIT` (0.92) model units.
- **The pivot is the point that stays still while it turns**, and the pixel the
  body is drawn at: the bulk of the thing, where the hit circle is and what the
  shadow sits under. Floor along the page is foreshortened by the sine of the tilt
  and height by its cosine, which is what `foot` on each model (the pixels from the
  origin down to the floor under the pivot) is worked out from, and what the brains
  stand things on the page by.
- **The light lives in the room**, up, left and towards you, not on the model, so
  whichever way a body points it is lit from the top left.

### The solids

Every ray a body is asked is solved in closed form against a short list of shapes,
each in its own space:

| solid | what it is | the question |
| --- | --- | --- |
| `box` | an axis-aligned box | three slabs |
| `hull` | any convex polyhedron, as planes `n . p <= w` | one plane at a time |
| `cone` | radius changing linearly along an axis, flat at both ends; a cylinder is a cone with one radius | the slab between the ends, then a quadratic for the side |
| `ball` | a unit sphere | a quadratic |

Each answers an *interval* of the ray -- in at one face, out at another -- with the
normal at both ends. An ellipsoid is a ball put through an affine map (`Solid.ell`),
so it can lie at any angle; a capsule is approximated by an ellipsoid along it
(`Solid.lump`); the bake's rounded boxes are plain boxes, the crease along an edge
doing what a rounding a pixel wide did.

A **part** is one solid and what it is made of (`mat`, handed to the model's
`shade`), and optionally:

- `within`: kept only inside a second solid -- the marble's bust is kept inside its
  block. For convex solids that is two intervals overlapped, and the normal comes
  from whichever was entered last.
- `minus`: a list of solids taken out -- the whistle's window, the metronome's
  panel, the marble's eye sockets. A ray that goes in somewhere inside a cut is
  stepped through to the cut's far wall, which is a surface whose normal is the cut's
  own turned round; `shade` is told it is a cut, which is how the window is painted
  ink.
- `clip`: planes the part is cut off at -- the marble's chest flat under the
  shoulders, its hair off the face and above the ears, the dictionary's spine cut to
  half a cylinder. Cheaper than a solid: a plane is turned into the room once a
  picture and is then a sum along the row.
- `move`: an affine map moving the part in the body -- the dictionary's front
  board, hinged at the spine.

A ray keeps the nearest part.

### Everything that moves is a map

Each solid sits in its part through its own map (`at`); each part can be `move`d in
the body; the whole body can be posed (`pose`, a function from the model's numbers
to a map: the stamp rocking on its heel); and the heading turns it about the pivot.
A ray is taken back through all of them into each solid's own space -- one affine
inverse per solid per picture -- where the question is the simple one, and the
normal comes back out through the transpose of the same inverse. Shading is asked
about the point in the *part's* rest space, so the stamp's label stays on its label
however it leans and the dictionary's board is painted the same lifted or shut.

### Light, ramps and lines

- **Diffuse** is the normal dotted with the lamp, and **specular** the half-vector
  to the camera to the 40th power, for the glint. The bake also cast shadows -- a
  second ray back towards the lamp from every lit pixel -- and the first live version
  kept them; they cost a quarter of every picture and showed as little more than the
  stamp's knob on its label, so they went.
- **The ramp.** The model's `shade` answers a palette key for the material and the
  point, or nothing for the red ramp every one of them is mostly made of:

  | condition | letter | colour |
  | --- | --- | --- |
  | specular > 0.6 | `w` | paper (the glint) |
  | diffuse > 0.78 | `k` | blush (lit) |
  | diffuse > 0.2 | `r` | red (middle) |
  | facing down and diffuse > 0.02 | `r` | red (light bounced off the page) |
  | otherwise | `s` | slate (shadow) |

  The other ramps the palette gives: blue (`w` glint, `c` sky, `b` blue, `s`) for
  the whistle's ring, grey (`w` paper, `g` graphite, `s` slate) for metal, paper and
  marble. **The bounce-light row is not optional**: without it the shadow side is
  one slate shape and reads as a hole cut in the body.
- **Creases:** where two neighbouring pixels of the same material have normals
  that disagree sharply (dot below 0.55), the lit or middle one steps down to
  slate. That is the edge where the barrel's flat face turns into its side; without
  it the planes merge into one blob.
- **Ink** round the silhouette -- any filled pixel next to an empty one -- and
  along any step in depth of more than `edge` model units *where the nearer pixel
  is another part*. Only another part: one surface seen at a grazing angle steps in
  depth from pixel to pixel too, and the first try drew stripes down the reared
  stamp's top.
- Details that are **holes or print** are tested in the part's own space at the hit
  point and painted directly: the whistle's mouth, the metronome's scale, the
  stamp's label, the dictionary's thumb index and title, the marble's veins and
  chisel strokes.

### What it costs, and how it is kept cheap

LÖVE on a phone may well be running the interpreter rather than the JIT, so the
number that matters is the interpreted one, and the yardstick is the piggy bank,
which repaints every frame it changes and costs about a millisecond a picture on a
desktop interpreter. The first live version cost two to six times that. What
brought it down to the pig's, near enough -- a millisecond for the stamp and the
whistle, one and a half to two for the metronome and the dictionary -- is:

1. **Ask only what can be hit.** Each solid's box is put through its maps onto the
   screen each picture, and a pixel asks a part only inside both the rectangle its
   corners land in and the circle its bounding sphere does (each is tighter than
   the other for some shape). Parts are asked nearest first, part by part over their
   own pixels, and a part whose nearest point is further than what a pixel already
   holds is not asked at all. A cut is asked only inside its own rectangle.
2. **Carry the ray along the row.** Every ray of a picture goes the same way, and
   from one pixel to the next its origin moves the same step, in every solid's own
   space. So the origin is stepped rather than transformed, a box's way in and way
   out of each pair of faces is a start and a step (three maxes and three mins a
   pixel), a hull's distance inside each plane likewise, and the planes a part is
   cut off at (`clip`) are turned into the room once a picture. A normal is turned
   out of its solid's space only for the part that wins the pixel.
3. **Solve what is shared once.** The marble's block, which every piece of its bust
   is kept inside, is solved once a pixel into buffers the pieces read, and a pixel
   already on the block's face is not asked again by anything inside it.
4. **Write it for the interpreter and the JIT both.** No assignment of several
   values at once in the hot loops, and results left in upvalues rather than
   returned eight at a time -- LuaJIT gives up compiling a trace over either (the red
   pen's lesson).
5. **Keep the pictures.** The heading is drawn to a ninety-sixth of a turn and every
   number the picture depends on to its model's `steps`, and a picture is kept under
   that key, a hundred and sixty to a model and shared by every body of it. Reuse is
   exact -- a kept picture is the picture -- so a boss circling you, or turning on
   the library's turntable, mostly costs nothing, and the marble's carving is drawn
   in forty steps from block to bust.

A picture that is not kept is painted in the frame it is needed, all at once, as the
pig's is. An earlier version painted new pictures a slice a frame in a coroutine and
went on drawing the last one finished; on a phone too slow to keep up with the
turntable that showed as headings jumping and, once, a picture finishing late and
flicking the body backwards. A frame now and then a little long is a price every
other live body already pays; a body shown somewhere it is not was a new kind of
bug, and painting in the frame makes it impossible.

The marble is the one still dearer than the pig -- two to three milliseconds while
it is barely started, one and a half finished -- and the fight pays for it rarely:
until it is roughed out it stands square to the page, so it is painted again only
when a hit carves it another step.

### Doing another character

1. **Add a row to `src/solids.lua`**: the pivot (the bulk of it), a `build` that
   answers the list of parts, and a `shade` for whatever is not the red ramp. Build
   it in made-up units at about a unit a pixel, front along −x.
2. **Look at it before the game does.** Paint every heading and pose into one image
   on a sample of the page it will stand on, scaled up with nearest-neighbour, and
   judge it there -- not at one heading. A dozen goes at a model is normal.
3. **Set `solid` on the enemy row**, and a `radius` that matches the bulk round the
   pivot, not the whole silhouette; `ground` on the model or the row if its feet are
   not the bottom of its picture.
4. **If it moves**, give the model the numbers it moves by (`rest`), a row of them
   per pose the brain names (`poses`), how fast each eases (`ease`), and which of
   them the picture depends on and how finely (`params`, `steps`). The brain sets
   `e.pose`; a number a brain drives directly is `e.solid:set(k, v)`.
5. **Check it in the game** with something walking a circle round it. For a boss,
   the title's dev BOSS button gets you straight to the fight.

### What was learned on the whistle

These were learned baking it and hold the same painting it live:

- **Don't model faces in 3D.** The first whistle painted eyes onto the barrel, and
  at sprite size perspective chewed them into something nobody could read. Anything
  that has to *read* -- eyes, a mouth, a symbol -- is laid flat and stamped on where
  the surface projects, or left off. The whistle dropped its face altogether; the
  marble's eyes are a red pixel each, put where the sockets project and only where
  the socket is what the camera sees there (`after` on its model).
- **A small angle beats a dramatic one.** A strong tilt made the mouthpiece stretch
  away up the screen. 34° shows the top without distorting the length.
- **Front-ish light.** Light from the side left half the body in slate. Light from
  top left *and* towards the viewer keeps most of what you see lit, with the shadow a
  band down one side.
- **Edge-on views are thin, and that's true.** Pointing straight at you or away,
  you're looking along a narrow object. A squat character turns better than a long
  one.
- **One sample a pixel, always.** Averaging is exactly what invents colours the
  palette doesn't have. Smoothness comes from the model's edges instead.

## A moving part on a live body: the metronome

The metronome's pendulum swings. It is not one of the body's solids: a rod a pixel
wide is a line, and a ray at a pixel's middle cannot be relied on to hit something
that thin, so it is plotted over the body every frame with `pixelart.line`, which
goes down at any angle because it is plotted, not a sprite. Its pivot, lean, length
and where the weight sits are `arm` on the model, in model units, and
`Metronome.armPoint` puts points on it through the body's own projection
(`Solid:project`). Three things make it sit on the body rather than float over it:

- **It uses the picture's heading, not the true one.** The body is drawn to a
  ninety-sixth of a turn; an arm turned to the exact angle would slide across the
  panel between one picture and the next, so `project` uses the map the picture
  being drawn was painted with.
- **Painter's order by heading.** When the panel faces away from the camera the arm
  is drawn first and the body covers it, so from behind only the tip shows over the
  cap; otherwise it is drawn after (`Metronome.armInFront`). A per-pixel depth test
  was not needed for one thin rod.
- **Its blank is its own.** The arm stands off the body, so it stamps its own paper
  under itself; the body's mask is only the body.

The same split serves any boss with one thin moving part: a needle, a wire, a lever.
Trace what has a surface, plot what is a line, and plot it through the body's own
projection.

## Poses: a body that moves

The stamp does not have a part that moves; the *whole thing* moves. It rocks back on
its heel before it jumps, pitches forward as it comes down and flattens when it
lands. Baked, each pose was a ring of pictures and the stamp snapped between them.
Live, a pose is **numbers**:

```
stand    tilt 0                       sx 1     sy 1
rear     tilt +20°  (about the heel)  sx 1     sy 1
lean     tilt −20°  (about the toe)   sx 1     sy 1
squash   tilt 0                       sx 1.12  sy 0.68
```

and the model's `pose` turns them into one map of the whole body: a scale about the
middle of the pad, then a turn about whichever edge of the mount is on the page
(`Affine.about`). The brain names a pose (`e.pose`) exactly as it did; the body eases
each number towards it at its own rate (`ease`): the rock over a tenth of a second,
the squash quicker -- an impact -- and back up at the same pace, so a landing springs.

- **Pose about the floor.** Every pose pivots on a point on the page -- the heel, the
  toe, the middle of the pad -- so no pose lifts the body off its shadow. Lifting is
  the game's job (`hop`, `Enemy:footing`), and a pose that lifted too would be two
  answers to one question.
- **Shade the unposed point.** `shade` is asked about the point in the stamp's rest
  space, so the label stays on the label however the body leans.
- **Bake what the game needs to line up -- in the model.** The pad has to land in a
  ledger cell, so it is sized from the page: 40px across is `40 * UNIT` units, and
  12px down the screen is a floor depth of `12 * UNIT / sin(PITCH)`. `foot`, the
  pixels from the origin down to the floor under the pivot, is what the brain seats
  it on a cell by.

## Poses with a hinge: the dictionary

The GRAMMAR boss is a fat dictionary lying on the page, and it is the stamp's method
with two things the stamp did not need.

- **A hinge is a part that moves.** `ajar` turns only the front board, about the line
  where it meets the spine: the board is a part with a `move` -- a turn about the
  hinge by `lift` -- and the pages and the spine are left where they are. Its
  underside is the endpaper, so a lifted board shows a white mouth; it is asked of
  the board's own rest-space point, lit whichever way it faces, because a slate
  inside reads as a hole. The board swings up over a tenth of a second and snaps
  down quicker: it bites.
- **A pose can be a different model.** `open` is not the shut book bent: it is its
  own list of parts, built about the spine, two leaves of boards and pages with the
  pages rising steeply out of the gutter to a crest and easing down to the fore-edge
  -- three planes across the top of each leaf, and the region under a top that only
  bends down is convex, so a leaf is one `hull`. Built about the spine because the
  spine is the middle of the move the game plays on it, so going from shut to open
  shifts the picture half a book, which only ever happens on a landing, where nobody
  is looking for it.
- **A clap is a fold.** Lying open, both leaves can stand up off the page about the
  gutter (`fold`, nought to a quarter turn), and the brain drives it as the clap's
  fore-edges sweep in (`src/dictionary.lua`): the book shuts from both sides on
  whoever is between them, which is what the move is named for.
- **Ask the model, not the normal.** "Is this the fore-edge?" has to be asked of the
  point in the model (its x), never of the room normal's x, which turns with the
  heading; only the normal's y, which no heading changes, is safe to read.

## Stages: a body carved away

ART's second boss is a block of marble with a bust in it. Its pose is not how it is
bent but how much of it is left, and it is one number, `carve`, from 0 (the block) to
4 (the bust), which the brain (`src/marble.lua`) sets off the boss's health: a whole
number at each of the row's thresholds and the way between them in between, so every
hit takes a little marble off, not only the hits that cross a threshold.

- **One model, grown by a margin.** The bust is modelled whole -- socle, chest, neck,
  head, jaw, nose, brow, ears, the sockets of the eyes and a cap of hair -- and every
  stage is each of its solids grown by a margin and kept inside the block (`within`).
  The margins are the bake's five stages (16, 7, 4, 1.8, 0) and `carve` runs between
  them. No margin is the bust; a margin past the block's size is the block; between,
  the bust grown and cut square wherever it still reaches the block's faces -- which
  is what makes the in-betweens read as carving rather than as a blob shrinking: the
  flat faces the block came with stay on wherever the stone has not been touched yet.
- **Only what can still be seen.** Grown far enough, the nose, the brow and the ears
  reach past the block's faces and are cut flat by them, and the socle's waist is
  swallowed by what is round it, so a block barely started is seven solids rather
  than thirteen. The jaw and the neck stay at every margin: they fill the waist
  between the head and the chest, and leaving them out turned the hewn block into a
  stack of lumps.
- **Rough is the margin, not a material.** While it is a pixel or more out from the
  finished bust, the stone is drawn rough -- chisel strokes a step darker in the
  model's own space, so they stay on the stone as it turns; at the end it is polished.
  The veins are a field of the model point, so a deeper stage shows more of the same
  veins, never new ones. The finished face is kept clear of them, so the eyes the
  brain opens there are the only red on it.
- **The eyes are read off the picture.** As each picture of the finished bust is
  painted, the middle of each socket is projected, and kept if the depth the camera
  sees at that pixel is the socket's (`after` on the model): eyes on the back of the
  head are not drawn.

The brain keeps the half-made stages facing the page (`e.face`) and lets the finished
ones turn to watch you.

## Painted live on flat faces: the die

The MATHS boss (`src/dice.lua`) is a d6, then a d10, then a d20, and it was the
first boss painted live while the whistle was still baked, for a reason worth
keeping in mind for any future character: **a die has no front.** Baked views paid
for headings -- sixteen pictures of a thing turning to face you -- and what a die
needs is to tumble end over end in any direction and come to rest on any face.
Baking that would have been a picture for every orientation, which is not a budget;
painting it fresh each frame costs about what the eye does.

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
not convex and is a row in `src/solids.lua`, with the dent as a `minus`.

## Painted live under a moving light: the still life

The ART boss (`src/plaster.lua`) is a plaster cube, sphere and cone on a table under a
lamp, and it is painted live for a reason none of the others needed: **the light
moves.** Every other boss in this file is lit from one window fixed in the room, so
it only ever has to be lit one way. The still life's whole fight is the lamp
going round it (`src/stilllife.lua`), and the body has to show where the lamp is --
the lit side of each solid following it round -- before the shadows on the floor say
so. Baked, it would have been a picture for every heading of the lamp on top of
every heading of the body. Painted, it is one dot product per pixel.

What is new here, against the die:

- **Three kinds of solid, nearest wins.** Each piece is met by the ray its own way:
  the cube is the die's planes (with its own turnable axes, so it can tumble when
  thrown), the sphere is the eye's disc, and the cone is a quadratic off its apex `A`
  and unit axis `D` -- the points `Q = X - A` with `(Q.D)^2 = c2 |Q|^2`, `c2` the
  squared cosine of its half-angle, `0 <= Q.D <= h`, plus the base as a plane a whole
  height down the axis. Its outward normal is `c2 Q - (Q.D) D`. Given by apex and axis,
  one piece of code stands it on its base, lays it on its side and spins it on its
  point. Every piece answers a depth, and the nearest is the pixel's.
- **The silhouette and the light are kept apart.** The raster keeps, per pixel, an
  id (`piece * 16 + face`) and the screen normal. It is redone only when a piece moves
  (`Plaster:touch`); the lamp moving redoes nothing but the shading, which is the
  normal dotted with the direction from that piece's middle to the lamp. A lamp
  brought in close lights the near side of the group and not the far.
- **Edges from ids,** the die's test across pieces as well as faces: the line where
  the sphere sits in front of the cube comes out of the same check as the cube's own
  creases.
- **A pencil ramp, and fill light.** Plaster is drawn in pencil, so the ramp is
  paper, graphite and slate with checkers between, not red. Lit only by the lamp, a
  group with the lamp behind it is three slate holes; a `FILL` of light from where you
  are looking (the page bouncing it back) keeps the faces turned to you a step
  lighter than the ones turned away, so a cube lit from behind still reads as one.
- **Its shadows are the brain's.** Each piece's shadow is a wedge on the floor from
  the piece away from the lamp, as wide as the angle the piece subtends from it. Those
  are gameplay (the shade move fills them, and they hurt), so they are drawn and hit
  in page coordinates by `src/stilllife.lua`, not painted by the body.
- **Pieces leave the group.** A piece thrown off the table is hidden in the group and
  painted by a second `Plaster` of one piece where it is on the page, lit from the
  same lamp. Putting it back copies its turn into the group's piece, set square on the
  floor so a cube is never left balanced on an edge.

To add a solid of another kind, give it a constructor, a `prepare` (into the screen
once per raster) and a hit function answering depth, face and normal, and add it to
`HIT`. To make another boss this way, a group is a list of pieces and a `lamp`.

## Painted live with rings round it: the atom

SCIENCE's second boss (`src/atom.lua`) is the eye's sphere asked a different
question. Where the eye turns each pixel into the ball's frame and asks iris, pupil,
vein or white, the atom asks **which of twenty nucleons it is nearest** -- unit
vectors on a Fibonacci spiral, dealt protons and neutrons alternately -- and paints
an ink seam where the nearest two are nearly tied. That alone is a football. What
makes it a cluster of balls is shading each nucleon as **its own dome**: the light is
taken off a normal tipped away from that nucleon's middle (`BULGE` times the point's
offset from it, added to the sphere's own normal), so every ball has its own lit side
and its own shadow under the one fixed lamp. Nothing else is new; the turn, the
squaring-up and the row-run painting are the eye's.

The orbits are the other half, and they are not painted, they are **plotted**: each is
a circle in 3D given by a tilt off the page and a bearing (`Atom.point`), sampled a
pixel apart and projected straight down, with z only deciding whether a point is in
front of the nucleus or behind it -- the back half of every orbit is drawn first and
the nucleus covers it. Because the orbits are also what hurts, the brain
(`src/atomboss.lua`) tests the player against the same `Atom.point` samples the
drawing plots, so a ring hurts where it is drawn and nowhere else. The blank stamped
under the body (`drawMask`) is the nucleus only: an orbit is a line on the page, and
blanking under it would cut a white hoop through the ruling.

## Painted live from above, facing a way: the piggy bank

FINANCE's second boss (`src/piggy.lua`) is the eye's method with three things
changed, and each is a small step rather than a new idea.

**More than one solid, all ellipsoids.** A pig is a barrel, a snout, two ears, four
legs and a tail, and each of them is an ellipsoid given as a middle and three
half-lengths in the pig's own frame (nose, side, back). A pixel's ray is a straight
line into the page, so in the pig's frame each of the three coordinates along it is
`alpha + z * beta`, and "is it inside" is a quadratic in z: the nearer root is where
the ray meets that solid. Every pixel asks the solids it could be on (a circle test
on each one's screen position first) and keeps the nearest. The normal is the
gradient of the solid's sum, turned back onto the screen, and the eye's lamp lights
it; the snout's flat face, its nostrils, the eyes and the slot are picked off the
hit point's coordinates on whichever solid it is.

**Seen from above, so it can face a way.** The eye and the atom are looked at
straight down, where every heading looks the same. The pig is looked at half a
radian above the page (`ELEV`): the page's up-the-page becomes "into the screen and
up", so its frame for a heading `yaw` is its nose along the heading on the page, its
side across it, and its back tipped towards you. Turning the pig is changing `yaw`;
nodding it is a `pitch` about its side. Nothing is rotated at draw time -- the
picture is painted fresh for whatever way it is facing, which is what the whistle's
sixteen baked views did ahead of time, and what moved the whistle onto this method
in the end (**Built of simple solids**).

**Edges inside the silhouette.** One sphere has only a rim. Nine solids have places
where one stands in front of another -- an ear against the barrel, a near leg against
the belly -- and those need a line too, or the pig is one pink blob. The picture is
worked out into a depth buffer first, and any pixel whose neighbour is more than
`EDGE` nearer is drawn ink: a contour on the far side of every step in depth, the
same one-pixel line the rim is.

And the cracks are the atom's seams: the barrel's hit point, wobbled a little and
normalised, is asked which of eighteen shards it is nearest, and the seam between
the two nearest is drawn once both are reached by the damage. Shards are reached in
order of their distance from one spot, so the web grows out from where it started.

Because the picture is now several solids and an edge pass, it is worked out once a
frame into rows of runs (`Piggy:raster`) and kept: the blank under it, the hit's
rim and the body all read the same rows.

## Painted live with flat ends: the speaker

MUSIC's second boss (`src/speaker.lua`) is a cylindrical bluetooth speaker, and a
cylinder is the piggy bank's method with one change: the solid has flat ends, so
every ray asks two kinds of question.

1. **The side** is the ellipsoid's quadratic with the axis term left out: the
   ray's body coordinates are `a + z * b` along the can's front, side and axis,
   and the side is where `front^2 + side^2 = radius^2`. The nearer root counts
   only if the axis coordinate there is inside the half height.
2. **The caps** are planes, so a division: `z = (+-half - a_u) / b_u`, counted
   only if that point is inside the radius. The nearest of the three hits wins.
3. **A frame, not a heading.** The pig only turns about the upright. The speaker
   tips over and rolls, so its orientation is three page vectors (front, side,
   axis) turned by Rodrigues' formula each frame and put square again. Facing you
   is a turn about the page's up; tipping is a turn about the way it will roll
   (which lays the axis across it); rolling is a turn about `up x heading`, which
   is the axis once it lies; a bounce turns the whole frame about the page's up by
   the angle the box turned its heading. Standing up is a turn about `axis x up`.
4. **Squash.** The radius and half height are scaled against each other and the
   middle is put back at its new height off the page, so the foot stays put and
   the can, not the page, gives.
5. **Texture in the can's own coordinates.** Everything that makes it a speaker
   is painted off where on the can a pixel is, not where on the screen: ribs of
   the knit every few units up the axis (ellipses on the screen, the strongest
   round cue in the picture, and what shows it roll), the + and - as lengths
   round the can and up it with an ink keyline, a rune on the back, the ring of
   lights by angle round the top, and the radiator lit off a normal pushed out by
   `pump`, so its light swells on the beat while not one pixel of it moves.

The rim and the depth edges are the pig's, and the picture is worked out once a
frame into rows of runs (`Speaker:raster`). It is about the cost of the pig: one
solid, but three questions per pixel instead of nine.

## Painted live along its own length: the red pen

GRAMMAR's second boss (`src/redpen.lua`) is a click pen 260 long, and it is the
speaker's method with three changes, each forced by the length.

1. **Cones as well as cylinders.** A pen is a solid of revolution: a metal tip, a
   cone in front of the grip, the long body, a narrower button. Each piece is a
   radius that changes linearly along the axis, `r = c + m * u` (a cylinder is
   `m = 0`), and with the ray as `A + t B`, the point's axis coordinate is
   `u = A.U + t B.U`, so `|A + t B|^2 - u^2 - (c + m u)^2 = 0` is one quadratic in
   `t` for every piece. The nearer root counts if its `u` is inside the piece; if
   not, the further one (the inside of a cone seen past its rim). The two flat
   ends -- the barrel's, round the button, and the button's own -- are the
   speaker's planes. The normal on a cone is the radial direction minus `m` times
   the axis. One function (`piece`) answers all four.
2. **An oblique view, one to one.** The speaker is seen from above at an angle, its
   depth squeezed into the screen. The pen cannot be: when it falls, the line it
   lands on is a line on the page, and the strip it warned you about has to be
   that line to the pixel. So a point `(x, y, h)` on the page is drawn at
   `(x, y - K h)` -- the page itself one to one, as everything else on it is drawn,
   and height going up the screen at `K` (0.8). The ray for a pixel is then the line
   through the page under it going `(0, K, 1)`: up, and towards you.
3. **A band, not a box, and only what is seen.** Stood up it goes off the top of
   the screen; lying down it crosses the whole box. Tracing a square round its
   middle would be most of a screen of rays, nearly all missing. So the rows are
   walked over the band round the projected axis (as wide as the barrel can look,
   `R * sqrt(1 + K^2)`), cut to the camera's view (`Camera.bounds`, squared off to
   a 32px grid so a camera following you a pixel at a time is not a new view), and
   each ray is asked only about the pieces near its end of the band. It is traced
   again only when its axis, lift, roll or tip has moved: lying still, or glued,
   it costs nothing.

**Its frame** is just its axis `U`, set by the brain every frame. The front -- what
the print and the clip are placed round from -- is the direction back up the ray
with the axis taken out, so unrolled the print faces you whichever way the pen
points; `roll` turns it about the axis, which is what twiddling it and rolling it
across the page both are.

**Texture by where on the pen.** The grip's rings every few units of `u`, chrome
bands at two lengths, the clip as an angle round from the front over a stretch of
`u`, "0.7" as a 3x5 glyph laid along `u` and round the front -- all off the point's
own coordinates, so they turn and foreshorten with it.

It is the most expensive picture in the book, a couple of milliseconds at full
length on a desktop, against about one for the speaker. Most of that is the number
of rays: it is a solid several screens of pixels long. The hot loop is split in two
(`ray`, which piece; `shade`, what colour) and avoids parallel assignments, both
so LuaJIT can keep it in registers; a row's buffers are arrays from the row's own
first column rather than tables keyed by screen columns, which go negative.

## Painted live out of stacked solids: the deodorant

P.E.'s second boss (`src/deodorant.lua`) is a can of body spray, and it is the
speaker's method made smaller in one way and larger in another.

1. **A heading, not a frame.** It never tips over, so the speaker's three page
   vectors come back down to the pig's single `yaw`, and the frame is built from it
   each raster: front, side and up, already on the screen.
2. **Three solids, nearest wins.** The can is a cylinder (side and top cap), its
   shoulder is the top half of an ellipsoid sat on the can's top -- one quadratic,
   kept only above the join -- and the button is a smaller cylinder through the
   shoulder. Each pixel asks all three and keeps the nearest front hit, which is
   the pig's rule for its nine ellipsoids with three solids instead.
3. **Print laid flat across the face, not round it.** AX3 is three letters of a
   3x5 face on a can 16 across, and laid out by distance *round* the can its outside
   columns turned away and smeared. Laid out by distance *across* the can (the side
   coordinate rather than the angle), facing you it sits a letter column to a pixel,
   and as the can turns the word squeezes off round the side the way print does. It
   is printed on a black panel whatever the lamp is doing, or the letters on the lit
   side are paper on graphite and vanish.

Everything else is the speaker's: the eye's lamp, ink at depth edges, rows of runs
worked out once a frame (`Deodorant:raster`). `swell` widens the solids for a glued
can's pressure, with the foot kept on the page.

## Projected live as lines: the tesseract

MATHS's second boss (`src/tesseract.lua`) is the one solid here with no surface
worth painting. A tesseract seen in three dimensions is a cube inside a cube with
the corners joined, and painting its faces would hide the inner cube, which is
the part that makes it a tesseract. So it is drawn as a wireframe, and the method
is the simplest in this file:

1. **Sixteen corners, thirty-two edges.** Every corner is +-1 on x, y, z and w.
   Every edge joins two corners that differ on one axis, and the axis it runs
   along is kept, because the eight that run along w are coloured apart.
2. **Turn in four dimensions.** Each frame the corners are turned in the x-w and
   z-w planes. A turn in a plane with w in it is what makes the inner cube flow
   out through the faces of the outer one.
3. **Perspective down w.** `k = DEPTH / (DEPTH - w)` and x, y, z are multiplied
   by it: the cube further along w comes out smaller. This is the step that makes
   it a cube *inside* a cube, and the same thing ordinary perspective does to z.
4. **Then an ordinary solid.** What comes out is a 3D wireframe. It is turned
   about the upright (`yaw`), looked at from `TILT` above the page, and projected
   straight on. The depth that comes out of that only orders the edges.
5. **Lines, back to front.** `pixelart.line` at any angle: far edges slate, near
   ones ink, the w struts red. The silhouette is the convex hull of the projected
   corners, filled a row at a time, so the blank, the rim and the flash are one
   honest shape.

It costs about a thousand single-pixel rectangles a frame, comparable to a
painted body, and needs no lamp and no per-pixel ray. The trade is that it can't
be shaded. The blush dither of the inner cube's hull is what stands in for a
surface.

## Smaller than a boss: the teardrop

The live method also works at five pixels across, for things whose *heading* is
the point. The eye's fan and its tears (`src/teardrop.lua`) are a ball with a
cone tangent to it, painted per pixel along whichever way the drop is moving on
the screen -- including the climb and fall of a thrown tear, which is what makes
its parabola read as one. At that size the ramp has room for two fills, one
glint pixel and the ink outline, and that is enough: what sells it is the shape
pointing the way it goes, not the shading. It costs one small box of pixel tests
per drop, which is fine for the few dozen a boss throws.

## Smaller than a boss, turning on the spot: the pickups

The heart, the ink drop, the diamond and the coin (`src/trinket.lua`) are the
method at nine pixels across with one change to how a ray finds the surface:
they are distance functions, marched rather than solved, because a heart and a
cut stone have no tidy closed form. Marching is slow, but nothing about a pickup
is live. What it looks like is which kind it is and how far round its turn it
is, so each kind is painted at 32 headings, each the first time it is wanted,
and kept, the tracer's pictures-by-heading at the smallest size. The ramp has
room for two fills, a checkered step between them, a glint and a rim, and the
rim is drawn in each kind's old outline colour so the colour code survives the
turn. Two things were learned at this size. A shape that is round about its
spin axis (the drop) shows nothing when spun, so it is leant over and the lean
goes round. And a heart's dip is a single pixel that the view from above fills
in with its own thickness, so the heart is seen almost side-on and has a notch
cut down the middle of its top.

## Where it fits and where it doesn't

- **Built of parts that face you:** something made of boxes, cylinders, cones and
  lumps that turns to face you and moves in poses is a row in `src/solids.lua` (the
  whistle, the metronome, the stamp, the dictionary, the marble).
- **Convex and tumbling:** a die, a crystal -- anything flat-faced that has to turn
  every way rather than face you -- is a face list painted by `src/dice.lua`.
- **Lit by something that moves:** a few simple solids whose shading has to follow a
  light around the page are a `Plaster` group (the still life).
- **Good fits:** bosses and anything else big (the whistle is 63 by 41 pixels),
  and objects whose heading matters, such as something that aims, or a weapon that
  should point the way it's going.
- **Poor fits:** the ordinary horde. A blob is eight pixels across, and at that
  size the ramp has room for about two shades, so a hand-drawn doodle reads
  better. The horde is also reskinned per lesson by hand
  (`Sprites.enemySkins`), and a rendered enemy would need every skin rendered
  too.
- **Not at all:** anything the player draws: the hero, the sword, the star and
  the rest of the drawn designs. Those are the player's own pixels.
- **Budget:** a few thousand rays a picture, about a millisecond, kept by heading
  and pose (**What it costs**, above). One boss on the page at a time is what that
  is sized for; a crowd of them would not be.
