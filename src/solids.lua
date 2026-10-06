-- The five bodies ray-traced live by src/solid.lua, as rows: the whistle, the
-- metronome, the stamp, the dictionary and the marble.
--
-- Each was modelled once as a distance field and baked into rings of ASCII
-- views (art/raytrace.py and a script a body); these are the same models again,
-- the same sizes in the same units, built out of the solids a ray can be solved
-- against in closed form -- boxes and other flat-faced hulls, cones and
-- cylinders, ellipsoids -- with the same colours painted off the same places on
-- them. What the distance fields had that these do not is the soft blend where
-- one rounded thing grows into the next; at a pixel to every model unit, what
-- that bought was a crease a pixel softer, and the edges between parts are
-- inked here instead (`edge`).
--
-- A row is:
--
--   pivot    the model point the body turns about and is drawn at: the bulk of
--            it, so the hit circle on the enemy's row is round the middle
--            (`foot`, worked out below, is how far under it the floor is)
--   ground   how far below the origin the shadow goes, where the row has no
--            `ground` of its own
--   rest     the numbers its pose is made of, as they start
--   poses    a row of those numbers for every pose a brain names (`e.pose`)
--   ease     how fast each number goes where it is going, a second; a number
--            with none snaps
--   params   which of the numbers the picture depends on, and `steps`, how
--            finely each is drawn: pictures are kept by heading and by these,
--            so a body back in a pose it has been in is not painted again
--   pose     the numbers into an affine map of the whole body (rest to posed)
--   build    the numbers into the list of parts (src/solid.lua's `part`)
--   shade    a hit into a palette key, or nil for the red ramp: handed the
--            point in the part's own rest space, the part, the diffuse and the
--            glint, the room normal, whether the surface is the wall of a cut,
--            and the numbers
--   edge     the step in depth, in model units, that is drawn as an ink line
--   after    anything to be read off a picture as it is painted (the marble's
--            eyes, and whether they can be seen)
--
-- Model space is the bake's: front along -x, y up off the page, z across, the
-- floor at y = 0.

local Solid = require("src.solid")
local Affine = Solid.Affine

local sqrt, sin, cos, floor, abs = math.sqrt, math.sin, math.cos, math.floor, math.abs
local max = math.max
local box, hull, cone, cyl, ell, lump, part =
    Solid.box, Solid.hull, Solid.cone, Solid.cyl, Solid.ell, Solid.lump, Solid.part

local Solids = {}

-- The three grey steps (paper, graphite, slate) the metal and the paper parts
-- of every one of them are lit on.
local function grey(diff, spec, hi, lo)
    if spec > 0.6 or diff > hi then return "w" end
    return diff > lo and "g" or "s"
end

--- the whistle -------------------------------------------------------------------------

-- The P.E. boss: a coach's whistle, red because a body this big can only say one
-- thing on the page and the thing is "theirs". A wheel of a barrel with its axis
-- across, a mouthpiece out of the front with the window cut into its top, and the
-- lanyard ring on the back in blue. The barrel's middle is the pivot, which is
-- the drum the hit circle is (`radius` in src/enemy.lua).
do
    local BX = 7.0
    -- The mouthpiece: a box whose bottom slopes up towards the mouth, flat on
    -- top, 26 long; and the window let into its top over the barrel's lip.
    local tube = hull({
        { 1, 0, 0, 4 }, { -1, 0, 0, 22 },
        { 0, 1, 0, 11.5 }, { -0.1, -1, 0, -2.9 },
        { 0, 0, 1, 4.6 }, { 0, 0, -1, 4.6 },
    }, { -22, 2.5, -4.6, 4, 11.5, 4.6 })
    local window = function() return box(-1.0, 10.8, 0, 3.6, 3.4, 3.6) end
    local parts = {
        part(cyl("z", BX, 0, 0, 6.5, 11.5), "body", { minus = { window() } }),
        part(tube, "body", { minus = { window() } }),
        -- The ring: a flat washer where the bake had a torus -- a torus is a
        -- quartic, and at three pixels across a washer is the same drawing.
        part(cyl("z", BX + 9.5, 9.5, 0, 0.9, 3.9), "ring",
            { minus = { cyl("z", BX + 9.5, 9.5, 0, 1.2, 2.1) } }),
    }

    Solids.whistle = {
        pivot = { BX, 0, 0 },
        ground = 15,
        edge = 3,
        build = function() return parts end,
        -- The two holes are ink, where they are: the window's walls and the mouth
        -- in the end of the tube. The ring is metal on the blue steps.
        shade = function(x, y, z, p, diff, spec, nx, ny, nz, cut)
            if p.mat == "ring" then
                return diff > 0.7 and "c" or diff > 0.3 and "b" or "s"
            end
            if cut and y < 10.6 then return "o" end
            if x < -21.0 and abs(z) < 3.0 and y > 7.6 and y < 10.6 then return "o" end
        end,
    }
end

--- the metronome -------------------------------------------------------------------------

-- The MUSIC boss: a pyramid metronome on a plinth, red, with a paper panel let
-- into its front for the tempo scale and a metal key out of its right side --
-- which is what tells you which way round it is when it turns. The pendulum is
-- not one of these solids: it is plotted over the body every frame in this
-- same projection (src/metronome.lua, `arm` below), a line being the one thing
-- a pixel-wide rod can be.
do
    local BASE, TOP = 3.0, 34.0
    local DX0, DX1 = 9.0, 3.4
    local DZ0, DZ1 = 12.0, 4.0
    local KX = (DX0 - DX1) / (TOP - BASE)
    local KZ = (DZ0 - DZ1) / (TOP - BASE)
    local function depth(y) return DX0 - KX * (y - BASE) end
    local function width(y) return DZ0 - KZ * (y - BASE) end

    local PY0, PY1 = 6.5, 30.5
    local PK = 3.6 / (PY1 - PY0)
    local function panelHalf(y) return 6.2 - PK * (y - PY0) end

    local KY = 11.0
    local zs = width(KY) - 0.5

    local pyramid = hull({
        { 1, KX, 0, DX0 + KX * BASE }, { -1, KX, 0, DX0 + KX * BASE },
        { 0, KZ, 1, DZ0 + KZ * BASE }, { 0, KZ, -1, DZ0 + KZ * BASE },
        { 0, 1, 0, TOP }, { 0, -1, 0, -BASE },
    }, { -DX0, BASE, -DZ0, DX0, TOP, DZ0 })
    -- The panel: a trapezoid let 0.7 into the front face, narrowing up the face
    -- the way the face does, so its rim is a crease.
    local panel = hull({
        { 0, PK, 1, 6.2 + PK * PY0 }, { 0, PK, -1, 6.2 + PK * PY0 },
        { 0, 1, 0, PY1 }, { 0, -1, 0, -PY0 },
        { 1, -KX, 0, -DX0 - KX * BASE + 0.7 },
    }, { -DX0 - 1, PY0, -6.2, -DX1 + 1, PY1, 6.2 })
    local parts = {
        part(pyramid, "body", { minus = { panel } }),
        part(box(0, 1.6, 0, DX0 + 1.6, 1.6, DZ0 + 1.6), "body"),
        part(box(0, TOP + 1.4, 0, DX1 + 0.9, 1.4, DZ1 + 0.9), "body"),
        -- The winding key: a stub out of the side and a butterfly on its end.
        part(cyl("z", 0, KY, zs + 2.0, 2.2, 1.3), "metal"),
        part(box(0, KY, zs + 4.6, 0.7, 3.0, 0.6), "metal"),
    }

    local function onPanel(x, y, z)
        return y > PY0 and y < PY1 and abs(z) < panelHalf(y) and x < -depth(y) + 0.9
    end

    -- Where the pendulum hangs from, in model space: low on the panel, just proud
    -- of the face, leaning back with it; how long it is and how far up it the
    -- weight sits.
    local ARM_Y = 7.5

    Solids.metronome = {
        pivot = { 0, 15, 0 },
        ground = 24,
        edge = 3,
        arm = { x = -depth(ARM_Y) - 0.6, y = ARM_Y, z = 0, lean = KX, len = 38, bob = 0.62 },
        build = function() return parts end,
        -- Red is the tracer's default. The panel is paper down to graphite and
        -- slate, with the scale's ticks and the slot the arm hangs in down the
        -- middle painted where they fall; the key is metal on the same steps.
        shade = function(x, y, z, p, diff, spec)
            if p.mat ~= "metal" and not onPanel(x, y, z) then return nil end
            if p.mat == "body" then
                if abs(z) < 0.55 then return "s" end
                local tick = (y - PY0) % 3.0
                if abs(z) > 1.6 and abs(z) < 3.0 and tick < 0.9 and y < PY1 - 2 then return "s" end
            end
            return grey(diff, spec, 0.55, 0.15)
        end,
    }
end

--- the stamp ----------------------------------------------------------------------------

-- The FINANCE boss: an office rubber stamp -- a red wooden mount with a paper label
-- on top, a metal collar, a turned neck and a round knob to hold it by, and the
-- rubber underneath. Its pad is one cell of the ledger seen from the camera (40
-- across, 12 down), which is the point of it: the rubber under it covers the box
-- it is about to print. src/stamp.lua lands it on the printed cells.
--
-- **It moves as a whole**, which is what the poses are: rocked back on its heel
-- before it jumps (`rear`), pitched forward onto its toe as it comes down
-- (`lean`), pressed flat when it lands (`squash`). Each is two numbers -- a tilt
-- and a squash -- eased between, so the rock is a rock and the squash springs.
-- Every pose is about a point on the floor, so none of them lifts it off its
-- shadow: lifting it is the brain's (`hop`).
do
    local S = Solid.UNIT
    local PAD_Z = 40 * S / 2 - 0.6
    local PAD_X = 12 * S / sin(Solid.PITCH) / 2 - 0.6
    local PAD_H = 2.4
    local BLOCK_Y0, BLOCK_Y1 = PAD_H, 9.6
    local GROW = 0.8
    local NECK_Y0, NECK_Y1 = BLOCK_Y1, 17.5
    local NECK_MID = (NECK_Y0 + NECK_Y1) / 2
    local KNOB_Y = 21.5
    local HEEL = PAD_X + GROW
    local LABEL_X, LABEL_Z = PAD_X - 2.2, PAD_Z - 2.6
    local TILT = math.rad(20)

    local parts = {
        part(box(0, PAD_H / 2, 0, PAD_X, PAD_H / 2, PAD_Z), "rubber"),
        part(box(0, (BLOCK_Y0 + BLOCK_Y1) / 2, 0, PAD_X + GROW, (BLOCK_Y1 - BLOCK_Y0) / 2,
            PAD_Z + GROW), "body"),
        part(cyl("y", 0, BLOCK_Y1 + 0.8, 0, 1.4, 5.0), "metal"),
        -- Waisted, the way a turned handle is: two cones meeting half way up.
        part(cone("y", 0, NECK_MID, 0, NECK_Y0 - NECK_MID, 0, 3.4, 2.4), "body"),
        part(cone("y", 0, NECK_MID, 0, 0, NECK_Y1 - NECK_MID, 2.4, 3.4), "body"),
        part(ell(0, KNOB_Y, 0, 7.6, 5.6, 7.6), "body"),
    }

    Solids.stamp = {
        pivot = { 0, 6, 0 },
        edge = 3,
        -- `tilt` is rocked back on the heel when positive and forward onto the
        -- toe when negative; `sx` and `sy` are the squash, across and up.
        rest = { tilt = 0, sx = 1, sy = 1 },
        first = "stand",
        poses = {
            stand = { tilt = 0, sx = 1, sy = 1 },
            rear = { tilt = TILT, sx = 1, sy = 1 },
            lean = { tilt = -TILT, sx = 1, sy = 1 },
            squash = { tilt = 0, sx = 1.12, sy = 0.68 },
        },
        -- The rock over about a tenth of a second, and the squash quicker:
        -- it is an impact, and it springs back up at the same pace.
        ease = { tilt = 4, sx = 2.4, sy = 7 },
        params = { "tilt", "sx", "sy" },
        steps = { tilt = 0.035, sx = 0.02, sy = 0.02 },
        pose = function(p)
            local m = Affine.scale(p.sx, p.sy, p.sx)
            if p.tilt ~= 0 then
                local about = p.tilt > 0 and HEEL or -HEEL
                m = Affine.mul(Affine.about(Affine.rotate("z", -p.tilt), about, 0, 0), m)
            end
            return m
        end,
        build = function() return parts end,
        -- The wood is the tracer's red. The top of the mount carries a paper
        -- label with a red frame printed on it, which is what a stamp's label is
        -- (a proof of what it prints); the collar is metal; the rubber is dark,
        -- and red along its bottom edge where it is inked.
        shade = function(x, y, z, p, diff, spec)
            local m = p.mat
            if m == "metal" then return grey(diff, spec, 0.6, 0.2) end
            if m == "rubber" then
                if y < 0.8 then return "r" end
                return diff > 0.62 and "g" or "s"
            end
            if y > BLOCK_Y1 - 0.5 and y < BLOCK_Y1 + 0.4 and abs(x) < LABEL_X and abs(z) < LABEL_Z then
                local fx, fz = LABEL_X - abs(x), LABEL_Z - abs(z)
                if (fx > 1.3 and fx < 2.5 and fz > 1.3) or (fz > 1.3 and fz < 2.5 and fx > 1.3) then
                    return "r"
                end
                return diff > 0.45 and "w" or "g"
            end
        end,
    }
end

--- the dictionary --------------------------------------------------------------------

-- The GRAMMAR boss: a fat dictionary lying on the page -- red boards, a rounded
-- spine with raised bands, a block of pages with the thumb index cut into the
-- fore-edge, and a title panel on the cover. Its front is the fore-edge, the side
-- that opens, so a book facing you is a mouth facing you.
--
--   shut   closed, lying flat
--   ajar   the front board lifted off the pages about the hinge at the spine --
--          a book that bites; the board swings up and snaps down
--   open   lying open on its back, both leaves flat and the pages rising out of
--          the gutter; `fold` stands both leaves up off the page about the
--          gutter, which is the clap shutting (src/dictionary.lua drives it)
--
-- The open book is built about its spine rather than about the closed one's
-- middle, because the spine is where the game puts the middle of the clap:
-- going from shut to open moves the picture half a book, which happens on a
-- landing, where the eye does not look for it.
do
    local W, Z, T = 13.5, 16.5, 13.0
    local BOARD, INSET = 1.2, 0.9
    local SPINE_R = T / 2
    local SX = W - SPINE_R + 1.4
    local HINGE_X, HINGE_Y = W - 2.0, T - BOARD / 2
    local LIFT = math.rad(62)
    local NOTCHES = 6
    local LEAF = 2 * W - 0.6
    local GUTTER = 0.8

    -- The pages of one open leaf, `side` 1 or -1: a block from the gutter to
    -- the fore-edge whose top rises steeply out of the gutter to a crest and
    -- eases down to the fore-edge -- three planes, which is what its curve was,
    -- near enough, and the region under a curve that only bends down is convex.
    local function leaf(side)
        local x0, x1 = GUTTER, LEAF - INSET
        local xc = x0 + 0.28 * (x1 - x0)
        local xm = (x0 + xc) / 2
        local function top(xa, ya, xb, yb)
            -- y <= ya + (x - xa) * k  ->  -k x + y <= ya - k xa, along the side.
            local k = (yb - ya) / (xb - xa)
            return { -k * side, 1, 0, BOARD + ya - k * xa }
        end
        return hull({
            { side, 0, 0, x1 }, { -side, 0, 0, -x0 },
            { 0, 0, 1, Z - INSET }, { 0, 0, -1, Z - INSET },
            { 0, -1, 0, -BOARD },
            top(x0, 1.4, xm, 1.4 + 3.6 * sin(math.pi / 4)),
            top(xm, 1.4 + 3.6 * sin(math.pi / 4), xc, 5.0),
            top(xc, 5.0, x1, 3.7),
        }, { side > 0 and x0 or -x1, BOARD, -(Z - INSET), side > 0 and x1 or -x0, BOARD + 5, Z - INSET })
    end

    local function shutParts(p)
        local board = Affine.about(Affine.rotate("z", -p.lift), HINGE_X, HINGE_Y, 0)
        return {
            part(box(0, BOARD / 2, 0, W, BOARD / 2, Z), "cover"),
            part(cyl("z", SX, T / 2, 0, Z - 0.1, SPINE_R), "cover",
                { clip = { { -1, 0, 0, -(SX - 0.2) } } }),
            part(box(-INSET / 2, T / 2, 0, W - INSET / 2 - 1.2, (T - 2 * BOARD) / 2, Z - INSET), "pages"),
            part(box(0, T - BOARD / 2, 0, W, BOARD / 2, Z), "cover", { move = board, top = true }),
        }
    end

    local function openParts(p)
        local list = {}
        for _, side in ipairs({ -1, 1 }) do
            -- A leaf stands up about the gutter: the left one turned one way and
            -- the right the other, so both come up to meet over the spine.
            local up = Affine.rotate("z", side * p.fold * math.pi * 0.5)
            list[#list + 1] = part(box(side * LEAF / 2, BOARD / 2, 0, LEAF / 2, BOARD / 2, Z), "cover",
                { move = up })
            list[#list + 1] = part(leaf(side), "pages", { move = up })
        end
        return list
    end

    local function paper(diff, spec, line)
        if line then return diff > 0.45 and "g" or "s" end
        if spec > 0.6 or diff > 0.45 then return "w" end
        return diff > 0.12 and "g" or "s"
    end

    Solids.dictionary = {
        pivot = { 0, T / 2, 0 },
        rest = { lift = 0, open = 0, fold = 0 },
        first = "shut",
        poses = {
            shut = { lift = 0, open = 0, fold = 0 },
            ajar = { lift = LIFT, open = 0, fold = 0 },
            open = { lift = 0, open = 1, fold = 0 },
        },
        -- The board swings up over a tenth of a second and comes down quicker:
        -- a bite. Opening and the fold are the brain's to time.
        ease = { lift = 9, fold = 6 },
        params = { "lift", "open", "fold" },
        steps = { lift = 0.06, open = 1, fold = 0.04 },
        edge = 3,
        build = function(p)
            if p.open >= 0.5 then return openParts(p) end
            return shutParts(p)
        end,
        -- The boards are the tracer's red. The pages are paper on the grey ramp,
        -- ruled with grey lines of print where their faces are seen; the cover
        -- has a panel framed in slate with the title in paper, and the spine its
        -- raised bands; the fore-edge carries the thumb index -- the half-moons
        -- cut down the side of a dictionary to find a letter by.
        shade = function(x, y, z, p, diff, spec, nx, ny, nz, cut, n)
            if n.open >= 0.5 then
                if p.mat ~= "pages" then return nil end
                if y > BOARD + 1.2 and ny > 0.5 then
                    local ax = abs(x)
                    local line = abs(z) < Z - 3 and ax > GUTTER + 2.2 and ax < LEAF - INSET - 2.2
                        and (z + Z) % 2.6 < 0.9
                    return paper(diff, spec, line)
                end
                return paper(diff, spec, floor(y * 1.25) % 3 == 0)
            end
            if p.top and n.lift > 0.05 and y < T - BOARD * 0.55 then
                -- The board's underside, the endpaper: a lifted board shows a
                -- white mouth, lit whichever way it faces -- a slate inside reads
                -- as a hole rather than as paper.
                return (diff > 0.2 or ny < 0) and "w" or "g"
            end
            if p.mat == "pages" then
                local side = abs(ny) < 0.5
                if x < -W + 1.6 and side then
                    for k = 0, NOTCHES - 1 do
                        local zk = -Z + 3.2 + k * (2 * Z - 6.4) / (NOTCHES - 1)
                        local yk = T - BOARD - 1.2 - k * (T - 2 * BOARD - 2.4) / (NOTCHES - 1)
                        if (z - zk) ^ 2 + (y - yk) ^ 2 * 1.6 < 1.6 then return "o" end
                    end
                end
                if side then return paper(diff, spec, floor(y * 1.25) % 3 == 0) end
                -- The top of the block, seen when the board is up: lines of print.
                local line = abs(z) < Z - 3 and x < W - 4 and x > -W + 2.5 and (z + Z) % 2.6 < 0.9
                return paper(diff, spec, line)
            end
            if p.top and y > T - BOARD - 0.1 then
                -- The top: a panel framed in slate, a title in paper across it.
                local fx, fz = (W - 4.2) - abs(x + 1.0), (Z - 3.0) - abs(z)
                if (fx > 0 and fx < 0.9 and fz > 0) or (fz > 0 and fz < 0.9 and fx > 0) then return "s" end
                if fx > 0 and fz > 0 and abs(x + 1.0) < 1.2 and abs(z) < Z - 6.0 then
                    return diff > 0.4 and "w" or "g"
                end
            end
            if x > W - SPINE_R + 0.6 then
                -- The spine's bands.
                if abs(abs(z) - (Z - 3.0)) < 0.55 or abs(abs(z) - (Z - 6.0)) < 0.55 then return "s" end
            end
        end,
    }
end

--- the marble -----------------------------------------------------------------------------

-- ART's encore: a block of marble with a bust in it. The bust is modelled whole --
-- a round socle, a chest cut off under the shoulders, a neck, a head with a nose,
-- a brow, a jaw, ears, the sockets of the eyes and a cap of hair -- and so is the
-- block it is in, and the body is the block with everything more than `margin`
-- outside the bust cut off it: every solid of the bust grown by the margin and
-- kept inside the block. A margin past the block's size is the block as it came
-- out of the quarry; a margin of nought is the finished bust; every margin
-- between is the bust grown and cut square by the block's faces wherever it still
-- reaches them, which is what a block half carved looks like -- the flat faces it
-- came with, with a rounded lump knocked out of them where the head is going to
-- be. src/marble.lua sets the margin off the boss's health, so every hit takes a
-- little marble off.
--
-- **Rough and polished are told apart by the margin**: stone still a pixel or
-- more out from the finished bust is drawn rough, with chisel strokes a step
-- darker laid in the model's own space so they stay on the stone as it turns.
-- The veins are a field in the model's space too, so carving reveals more of the
-- same veins rather than painting new ones on: red and blush, the one thing on a
-- white body that says it is theirs.
do
    local BLOCK = { 0, 20.5, 0, 11.0, 20.5, 13.0 }
    -- How far the bust is grown at each of the bake's five stages: the block, hewn,
    -- roughed out, modelled, finished. `carve` runs from 0 to 4 through them.
    local MARGINS = { 16, 7.0, 4.0, 1.8, 0 }

    local function margin(carve)
        local k = math.min(4, math.max(0, carve))
        local i = math.min(4, floor(k))
        local f = k - i
        return MARGINS[i + 1] + (MARGINS[math.min(5, i + 2)] - MARGINS[i + 1]) * f
    end

    -- The block, which every piece of the bust is kept inside: one solid shared by
    -- all of them, so a ray asks it once.
    local function block()
        local b = box(unpack(BLOCK))
        b.shared = true
        return b
    end

    -- A plane a piece is cut off at (n . p <= w kept), grown by `m`.
    local function grown(p, m)
        local n = sqrt(p[1] ^ 2 + p[2] ^ 2 + p[3] ^ 2)
        return { p[1], p[2], p[3], p[4] + m * n }
    end

    -- Every solid of the bust, grown by `m`. The small ones are only there while
    -- they can still be seen: grown far enough, the nose, the brow and the ears
    -- reach past the block's faces and are cut flat by them, and the socle's
    -- waist is swallowed by what is round it -- so a block barely started is
    -- seven solids rather than thirteen. The jaw and the neck stay at every
    -- margin: they are what fills the waist between the head and the chest.
    local function bust(m)
        local list = {}
        local inside = block()
        local function add(upto, solid, mat, opts)
            if m >= upto then return end
            opts = opts or {}
            local clip
            for _, p in ipairs(opts.cut or {}) do
                clip = clip or {}
                clip[#clip + 1] = grown(p, m)
            end
            list[#list + 1] = part(solid, m > 0 and "rough" or mat,
                { within = inside, clip = clip, minus = opts.sockets })
        end
        local ALL = math.huge
        -- The socle: a base, a waist and a cap.
        add(ALL, cyl("y", 0, 1.2, 0, 1.6 + m, 8.8 + m), "marble")
        add(2, cone("y", 0, 4.4, 0, -2.4 - m, 0, 5.6 + m, 4.2 + m), "marble")
        add(2, cone("y", 0, 4.4, 0, 0, 2.4 + m, 4.2 + m, 5.6 + m), "marble")
        add(ALL, cyl("y", 0, 7.5, 0, 1.3 + m, 7.2 + m), "marble")
        -- The chest, cut off flat under the shoulders.
        add(ALL, ell(0.6, 15.0, 0, 6.2 + m, 6.8 + m, 11.6 + m), "marble",
            { cut = { { 0, -1, 0, -9.2 } } })
        -- The head: skull, jaw, neck, nose, brow and ears, and the sockets of the
        -- eyes taken out of the skull (only while there is a face to take them
        -- out of).
        local sockets
        if m < 1.5 then
            sockets = {}
            for _, zz in ipairs({ -2.7, 2.7 }) do
                sockets[#sockets + 1] = ell(-7.8, 31.3, zz, 1.7 - m, 1.3 - m, 1.5 - m)
            end
        end
        add(ALL, ell(0.0, 31.4, 0, 7.6 + m, 7.8 + m, 6.9 + m), "marble", { sockets = sockets })
        add(ALL, ell(-3.2, 27.0, 0, 4.6 + m, 3.4 + m, 5.0 + m), "marble")
        add(ALL, lump(0.8, 18.0, 0, -0.2, 26.0, 0, 3.4 + m), "marble")
        add(5.5, lump(-7.2, 31.6, 0, -9.4, 28.6, 0, 1.2 + m), "marble")
        add(5.5, lump(-6.7, 33.2, -3.4, -6.7, 33.2, 3.4, 1.2 + m), "marble", { sockets = sockets })
        for _, zz in ipairs({ -6.7, 6.7 }) do
            add(5.5, ell(1.0, 30.2, zz, 1.7 + m, 2.6 + m, 1.2 + m), "marble")
        end
        -- The hair: a cap, off the face and above the ears, swept back.
        add(ALL, ell(1.0, 32.6, 0, 8.2 + m, 8.0 + m, 7.6 + m), "hair",
            { cut = { { -1, 0.45, 0, 19.85 }, { 0, -1, 0, -28.6 }, { 0.3, -1, 0, -28.6 } } })
        return list
    end

    local function vein(x, y, z)
        local v = sin(0.17 * x + 0.11 * y - 0.14 * z + 1.6 * sin(0.15 * y + 0.11 * z)
            + 0.9 * sin(0.13 * x - 0.1 * z))
        return abs(v) < 0.075
    end

    -- Chisel strokes: short slanting dashes, a cell of the model each, half the
    -- cells struck. In the model's space, so they turn with it.
    local function rough(x, y, z)
        local u = 0.55 * x + 0.8 * y + 0.45 * z
        local v = 0.7 * x - 0.3 * y - 0.65 * z
        local cu, cv = floor(u / 4.5), floor(v / 2.6)
        local h = sin(cu * 12.9898 + cv * 78.233) * 43758.5453
        h = h - floor(h)
        if h < 0.55 then return false end
        local fu, fv = u / 4.5 - cu, v / 2.6 - cv
        return fu > 0.1 and fu < 0.9 and abs(fv - 0.5) < 0.17
    end

    Solids.marble = {
        pivot = { 0, 16, 0 },
        rest = { carve = 0 },
        -- Each hit's worth of marble comes off over a few frames rather than in
        -- one: chipped, not swapped.
        ease = { carve = 3 },
        -- Forty pictures from block to bust: one every fifteen health or so.
        params = { "carve" },
        steps = { carve = 0.1 },
        edge = 3,
        margin = margin,
        -- Where the finished bust's eyes are, from the origin: the middle of each
        -- socket, kept where the surface the camera sees there is the socket
        -- itself and not the back of the head. The brain opens them red once the
        -- bust is alive.
        after = function(c, q, at)
            c.eyes = {}
            if margin(q.carve) > 0.3 then return end
            for _, e in ipairs({ { -7.4, 30.6, -2.7 }, { -7.4, 30.6, 2.7 } }) do
                local i, j, seen, t = at(e[1], e[2], e[3])
                if seen and abs(seen - t) < 1.8 then c.eyes[#c.eyes + 1] = { i, j } end
            end
        end,
        build = function(p)
            local m = margin(p.carve)
            -- Kept on the numbers for `shade`, which would otherwise work it out
            -- again for every pixel.
            p.margin = m
            if m >= MARGINS[1] - 0.01 then
                return { part(box(unpack(BLOCK)), "rough") }
            end
            return bust(m)
        end,
        -- Marble is the grey ramp -- paper lit, graphite, slate -- with light
        -- bounced up off the page into the bottom of the shadow side.
        shade = function(x, y, z, p, diff, spec, nx, ny, nz, cut, n)
            local lit = (spec > 0.6 or diff > 0.55) and 3 or diff > 0.2 and 2
                or (ny < -0.55 and diff > 0.02) and 2 or 1
            local m = n.margin or margin(n.carve)
            if p.mat == "hair" then
                -- Locks: bands round the head, every other one a step down.
                if sin(1.3 * z + 0.6 * y + 0.9 * sin(0.8 * x + 0.5 * y)) > 0.2 then lit = max(1, lit - 1) end
            elseif p.mat == "rough" and m > 0.9 and rough(x, y, z) then
                lit = max(1, lit - 1)
            end
            -- The finished face is kept clear of veins, so the eyes the brain
            -- opens in it are the only red on it.
            local face = m < 0.3 and y > 24.5
            if lit > 1 and not face and vein(x, y, z) then return lit == 3 and "k" or "r" end
            return lit == 3 and "w" or lit == 2 and "g" or "s"
        end,
    }
end

-- How far below the origin the floor under the pivot is, in pixels, for every
-- one of them: where a brain stands what it does on the page -- the stamp's pad
-- in the middle of a cell, the dictionary's spine on the ruling, the marble's
-- chips from its foot. Height is foreshortened by the cosine of the camera's
-- tilt, so a pivot `y` up is `y cos(PITCH)` model units up the screen.
for _, model in pairs(Solids) do
    model.foot = math.floor(model.pivot[2] * cos(Solid.PITCH) / Solid.UNIT + 0.5)
end

return Solids
