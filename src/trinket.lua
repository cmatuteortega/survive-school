-- The pickups' bodies (src/pickup.lua): the heart, the ink drop, the diamond,
-- the coin, the wall clock, the alarm clock and the gold star, each a small solid
-- turning on the spot over its own shadow.
--
-- The bosses' method shrunk to nine pixels, as the teardrop showed it could be
-- (3dmethod.md): every pixel is a ray fired into the page, asked where it meets
-- the solid, and lit by the eye's screen-fixed lamp. The solids here are
-- distance functions rather than the tracer's closed forms -- a heart and a cut
-- stone have no tidy quadratic -- so a ray is marched rather than solved. That is
-- affordable only because nothing about a pickup is live: what it looks like is
-- which kind it is and how far round it has turned, and that is `STEPS`
-- pictures a kind, painted the first time each is wanted and kept for the run
-- (src/solid.lua keeps its pictures by heading for the same reason). Thirty
-- pickups on the page cost thirty sprite draws.
--
-- Why spin at all: a pickup is the one thing on the page that is a *prize*, and
-- the oldest way a game has of saying so is a thing turning in the air over the
-- floor. The turn also shows each one is a solid object -- the coin goes edge-on,
-- the heart thins to a sliver and fattens again, the diamond's facets catch the
-- lamp one after another -- which is what tells it apart from the doodles
-- printed on the page round it.
--
-- **No bigger than the hero.** Each is thirteen pixels across at most (the
-- hero's board is 15 by 19): a prize larger than the one who picks it up reads as
-- something to walk round rather than into. Thirteen and not the old sprites'
-- nine because the turn needs the room -- at nine the ramp had space for two
-- shades and a glint, and a solid with two shades reads as a flat sticker
-- changing shape rather than an object going round.
--
-- Drawn the eye's way otherwise: eight colours, no alpha, the ramp stepping down
-- through checkered pairs into slate, and a rim one pixel deep round the outside
-- in two colours -- the one the kind was always outlined in (red for health, blue
-- for ink, slate for the diamond, ink for the coin) on the side the lamp is on,
-- and a darker one on the side away from it. The rim going dark round the far
-- side is most of what makes something this small look round.

local Palette = require("src.palette")

local Trinket = {}

local sqrt, floor, sin, cos, abs, max, min = math.sqrt, math.floor, math.sin,
    math.cos, math.abs, math.max, math.min
local TAU = math.pi * 2

-- How many headings a turn is cut into. Thirty-two is a picture every eleven
-- degrees: at the fastest spin below that is a new picture every 40ms, which on
-- a thirteen-pixel body is as smooth as the turn can look.
local STEPS = 32

-- Seen from a little above, the piggy bank's way: the top of a thing tipped a
-- little towards you, so the coin turning edge-on is a thin ellipse rather than
-- a line, and the diamond shows its table.
-- The heart is the exception (`elev` on its row): seen from above, its own
-- thickness fills the dip between the lobes, and the dip is half of what makes it
-- a heart.
local ELEV = 0.3

-- Every solid below is written at the old sprites' size and blown up by this:
-- the shapes were tuned at nine pixels and a scale keeps them the same shapes.
local SIZE = 1.3

-- The eye's lamp: up, left and in front, fixed on the screen (y down, z at you).
local LX, LY, LZ = -0.48, -0.62, 0.62
do
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX, LY, LZ + 1
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end

-- The box a picture is painted in, about its centre: thirteen across and down
-- with slack each way for the rim, and the march's depth.
local BOX = 9
local DEPTH = 12

local paper, graphite, slate, ink = Palette.paper, Palette.graphite, Palette.slate, Palette.ink
local red, blush, blue, sky = Palette.red, Palette.blush, Palette.blue, Palette.sky

--- the solids -----------------------------------------------------------------
-- Each is a distance in its own frame: x across, y up, z through its face, in
-- pixels, centred on the middle of the body.

-- The heart: Inigo Quilez's 2D heart, pushed out into a pillow. A flat heart
-- turning is a playing card; a puffed one is a sweet, which is what it is.
local HEART_S = 7.5     -- the 2D shape is about 1.2 by 1.1; this makes it nine by eight
local HEART_Y = 4.1     -- lifts its point off the bottom so the middle is the middle
local HEART_T, HEART_R = 1.2, 1.0

local function heart2(x, y)
    x = abs(x)
    if y + x > 1 then
        local dx, dy = x - 0.25, y - 0.75
        return sqrt(dx * dx + dy * dy) - 0.35355
    end
    local ax, ay = x, y - 1
    local m = 0.5 * max(x + y, 0)
    local bx, by = x - m, y - m
    local d = sqrt(min(ax * ax + ay * ay, bx * bx + by * by))
    return x - y < 0 and -d or d
end

-- Quilez's heart dips barely a pixel between its lobes at this size, so a notch
-- is cut down the middle of the top: a heart is the dip as much as the point.
local NOTCH_Y, NOTCH_R = 4.6, 1.6

local function heart(x, y, z)
    local d2 = heart2(x / HEART_S, (y + HEART_Y) / HEART_S) * HEART_S
    local ny = y - NOTCH_Y
    d2 = max(d2, NOTCH_R - sqrt(x * x + ny * ny)) + HEART_R
    local dz = abs(z) - HEART_T
    local ox, oz = max(d2, 0), max(dz, 0)
    return min(max(d2, dz), 0) + sqrt(ox * ox + oz * oz) - HEART_R
end

-- The ink drop: a ball with a cone tangent to it, the teardrop's shape
-- (src/teardrop.lua) stood on end. It is round about its own axis, so a spin
-- would show nothing -- it is leant over instead (`DROP_LEAN`) and the lean goes
-- round, a drop wobbling like a top about to settle.
local DROP_R1, DROP_R2, DROP_H, DROP_Y = 3.4, 0.5, 5, 2.2
local DROP_B = (DROP_R1 - DROP_R2) / DROP_H
local DROP_A = sqrt(1 - DROP_B * DROP_B)
local DROP_LEAN = 0.32

local function drop(x, y, z)
    y = y + DROP_Y
    local q = sqrt(x * x + z * z)
    local k = -DROP_B * q + DROP_A * y
    if k < 0 then return sqrt(q * q + y * y) - DROP_R1 end
    if k > DROP_A * DROP_H then
        local dy = y - DROP_H
        return sqrt(q * q + dy * dy) - DROP_R2
    end
    return q * DROP_A + y * DROP_B - DROP_R1
end

-- The diamond: a brilliant cut -- a flat table, eight crown facets down to the
-- girdle and eight pavilion facets down to the point, the lower ring turned half
-- a facet so the two never line up. Flat faces under a lamp are what a turning
-- stone is for: each one flashes as it comes round.
local GIRDLE, GIRDLE_Y = 4.6, 1.6
local TABLE, TABLE_Y = 2.6, 3.4
local POINT_Y = -4.6
local FACETS = 8
local CROWN, PAVILION = {}, {}
do
    -- Each facet as the outward normal of the line it is cut along, in (out, up).
    local function cut(r1, y1, r2, y2, upward)
        local dr, dy = r2 - r1, y2 - y1
        local nr, ny = dy, -dr
        if (ny > 0) ~= upward then nr, ny = -nr, -ny end
        local n = sqrt(nr * nr + ny * ny)
        nr, ny = nr / n, ny / n
        return nr, ny, nr * r1 + ny * y1
    end
    local cr, cy, cd = cut(GIRDLE, GIRDLE_Y, TABLE, TABLE_Y, true)
    local pr, py, pd = cut(GIRDLE, GIRDLE_Y, 0, POINT_Y, false)
    for k = 0, FACETS - 1 do
        local a = k / FACETS * TAU
        CROWN[k + 1] = { cos(a) * cr, cy, sin(a) * cr, cd }
        PAVILION[k + 1] = { cos(a) * pr, py, sin(a) * pr, pd }
    end
end

local function diamond(x, y, z)
    local d = y - TABLE_Y
    for _, f in ipairs(CROWN) do
        d = max(d, f[1] * x + f[2] * y + f[3] * z - f[4])
    end
    for _, f in ipairs(PAVILION) do
        d = max(d, f[1] * x + f[2] * y + f[3] * z - f[4])
    end
    return d
end

-- The coin: a disc, the purse's coin given a thickness. The 1 on its face is
-- painted onto it below rather than cut into it -- at nine pixels a relief is
-- one shade and the figure would be lost in the ramp.
local COIN_R, COIN_T = 4.7, 1.1

local function coin(x, y, z)
    local dr = sqrt(x * x + y * y) - COIN_R
    local dz = abs(z) - COIN_T
    local ox, oz = max(dr, 0), max(dz, 0)
    return min(max(dr, dz), 0) + sqrt(ox * ox + oz * oz)
end

-- The purse's 1, three by five, on the face's own grid.
local FIGURE = { ".#.", "##.", ".#.", ".#.", "###" }

-- The wall clock: the coin's disc again, a little thicker, with the classroom
-- clock's face painted on it -- a black bezel, a paper dial, and the hands at
-- three o'clock, an L that reads as a clock at nine pixels where the poster
-- clock's ten past ten reads as a tick. The dial is on both faces for the coin's
-- reason: half of every turn is the back, and a prize you can only read half the
-- time is half a prize.
local CLOCK_R, CLOCK_T = 4.8, 1.2
local DIAL = 3.6      -- inside this, dial; outside it, bezel
local HAND_W = 0.62   -- half a hand's width: under a pixel at SIZE and the
                      -- march misses it, over and the hands are blobs

-- How far (x, y) is from the segment out of the middle to (hx, hy).
local function hand(x, y, hx, hy)
    local t = max(0, min(1, (x * hx + y * hy) / (hx * hx + hy * hy)))
    local dx, dy = x - hx * t, y - hy * t
    return sqrt(dx * dx + dy * dy)
end

-- A clock face at (x, y) on its own grid: the hands, then the bezel, then the
-- dial. Shared by the wall clock and the alarm clock, which differ in how big a
-- dial they have and what goes round it.
local function dial(x, y, r, hourX, minY)
    if hand(x, y, hourX, 0) < HAND_W or hand(x, y, 0, minY) < HAND_W then
        return "hand"
    end
    if sqrt(x * x + y * y) > r then return "bezel" end
    return "dial"
end

local function clock(x, y, z)
    local dr = sqrt(x * x + y * y) - CLOCK_R
    local dz = abs(z) - CLOCK_T
    local ox, oz = max(dr, 0), max(dz, 0)
    return min(max(dr, dz), 0) + sqrt(ox * ox + oz * oz)
end

-- The alarm clock: a squat drum on two feet with the two bells on its head and
-- a knob between them -- the one drawing of an alarm clock everybody knows. Red
-- all over because it is the fire alarm of the page (Pickup's `alarm`): red is
-- the other side in every module, and this is the one prize that goes off.
local ALARM_R, ALARM_T = 3.9, 1.7
local BELL_X, BELL_Y, BELL_R = 2.75, 3.55, 1.6
local KNOB_Y, KNOB_R = 4.35, 0.65
local FOOT_X, FOOT_Y, FOOT_R = 2.5, -3.95, 0.8
local ALARM_DIAL = 2.8

local function ball(x, y, z, cx, cy, r)
    local dx, dy = x - cx, y - cy
    return sqrt(dx * dx + dy * dy + z * z) - r
end

local function alarm(x, y, z)
    local dr = sqrt(x * x + y * y) - ALARM_R
    local dz = abs(z) - ALARM_T
    local ox, oz = max(dr, 0), max(dz, 0)
    local d = min(max(dr, dz), 0) + sqrt(ox * ox + oz * oz)
    local ax = abs(x)
    d = min(d, ball(ax, y, z, BELL_X, BELL_Y, BELL_R))
    d = min(d, ball(ax, y, z, 0, KNOB_Y, KNOB_R))
    return min(d, ball(ax, y, z, FOOT_X, FOOT_Y, FOOT_R))
end

-- The gold star, puffed: Inigo Quilez's five-pointed star pushed out into a
-- pillow the heart's way. A flat star turning is a sheriff's badge; a puffed one
-- is the sticker on the top of a page, which is what it is. Sized so its points
-- span the thirteen pixels and no more.
local STAR_R, STAR_IN = 5.0, 0.48
local STAR_T, STAR_ROUND = 0.9, 0.7
local K1X, K1Y = 0.809016994, -0.587785252

local function star2(x, y)
    x = abs(x)
    local d = 2 * max(K1X * x + K1Y * y, 0)
    x, y = x - d * K1X, y - d * K1Y
    d = 2 * max(-K1X * x + K1Y * y, 0)
    x, y = x + d * K1X, y - d * K1Y
    x = abs(x)
    y = y - STAR_R
    local bx, by = STAR_IN * -K1Y - 0, STAR_IN * K1X - 1
    local h = max(0, min(STAR_R, (x * bx + y * by) / (bx * bx + by * by)))
    local px, py = x - bx * h, y - by * h
    local l = sqrt(px * px + py * py)
    return (y * bx - x * by) < 0 and -l or l
end

local function star(x, y, z)
    local d2 = star2(x, y + 0.35) + STAR_ROUND
    local dz = abs(z) - STAR_T
    local ox, oz = max(d2, 0), max(dz, 0)
    return min(max(d2, dz), 0) + sqrt(ox * ox + oz * oz) - STAR_ROUND
end

--- the ramps ------------------------------------------------------------------
-- Down the light, brightest first: past `at` a pixel is the first colour, or the
-- two checkered when there are two. The last row catches everything left.

local RAMP = {
    heart = {
        { at = 0.45, blush }, { at = 0.2, blush, red },
        { at = -0.15, red }, { at = -0.45, red, slate }, { at = -2, slate },
    },
    ink = {
        { at = 0.45, sky }, { at = 0.2, sky, blue },
        { at = -0.15, blue }, { at = -0.45, blue, slate }, { at = -2, slate },
    },
    -- Cut from paper, as it always was: like the eye and the ruler body it is
    -- the paper side of the ramp that does the work, and sky is its shade.
    diamond = {
        { at = 0.8, paper }, { at = 0.55, paper, sky },
        { at = 0.25, sky }, { at = -0.1, sky, blue }, { at = -0.4, blue },
        { at = -2, blue, slate },
    },
    coin = {
        { at = 0.35, blush }, { at = 0.05, blush, red },
        { at = -0.3, red }, { at = -2, red, slate },
    },
    -- The wall clock's ramp is its dial's, paper going down to graphite; the
    -- bezel and the edge are stepped off it in its `face` below.
    clock = {
        { at = 0.3, paper }, { at = 0.0, paper, graphite },
        { at = -0.35, graphite }, { at = -2, graphite, slate },
    },
    alarm = {
        { at = 0.45, blush }, { at = 0.2, blush, red },
        { at = -0.15, red }, { at = -0.45, red, slate }, { at = -2, slate },
    },
    -- Purple, which the palette does not have and is not allowed to grow: it is
    -- red and blue checkered pixel by pixel, the way every in-between shade on
    -- the ramps is made, and their light ends checkered over it. Slate -- the
    -- palette's own purple-grey -- is the shade, so the dark side lands on a
    -- colour that was already the right hue. It is the one thing on the page
    -- that is both sides at once, which is why a thing that makes *everything*
    -- hit harder wears it.
    star = {
        { at = 0.72, blush, sky }, { at = -0.1, red, blue },
        { at = -0.45, blue, slate }, { at = -2, slate },
    },
}

-- How fine a highlight is: past this along the half-way vector, paper. A
-- diamond's is wide on purpose, so a whole facet flashes as it comes round.
local GLINT = {
    heart = 0.96, ink = 0.97, diamond = 0.9, coin = 0.96,
    clock = 0.97, alarm = 0.96, star = 0.95,
}

--- the kinds ------------------------------------------------------------------
-- `turns` is turns a second, `lean` a tilt applied before the turn, and `face`
-- anything painted on top of the ramp, handed the point it hit in its own frame.

local KINDS = {
    heart = { sdf = heart, rim = red, dark = slate, turns = 0.55, elev = 0.12 },
    ink = { sdf = drop, rim = blue, dark = slate, turns = 0.7, lean = DROP_LEAN },
    diamond = { sdf = diamond, rim = slate, dark = ink, turns = 0.4, elev = 0.12 },
    -- Seen from higher than the rest, so its milled edge shows as a band under
    -- the face rather than a line.
    coin = {
        sdf = coin, rim = ink, dark = ink, turns = 0.8, elev = 0.45,
        -- The 1 on both faces, read the right way round from either side, and
        -- the milled edge a step darker than the face.
        face = function(x, y, z, colour)
            if abs(z) > COIN_T - 0.35 then
                local fx = z > 0 and x or -x
                local col, row = floor(fx + 1.5) + 1, floor(2.5 - y) + 1
                local line = FIGURE[row]
                if line and col >= 1 and col <= 3 and line:sub(col, col) == "#" then
                    return paper
                end
                return colour
            end
            -- The edge: the face's ramp a step down, so the band reads as the
            -- side of a thick coin and not more of its face.
            if colour == blush then return red end
            if colour == red then return slate end
            return colour
        end,
    },
    -- Seen from a little higher than the coin is not: the dial wants facing
    -- you, and the edge is a band of black under it either way.
    clock = {
        sdf = clock, rim = slate, dark = ink, turns = 0.6, elev = 0.2,
        face = function(x, y, z, colour)
            if abs(z) > CLOCK_T - 0.35 then
                local fx = z > 0 and x or -x
                local part = dial(fx, y, DIAL, 2.2, 3.1)
                if part == "hand" then return ink end
                if part == "bezel" then return colour == paper and slate or ink end
                return colour
            end
            return colour == paper and slate or ink
        end,
    },
    -- The dial only on the front, because an alarm clock's back is its winding
    -- keys and a plain red tin: turned away it is a red drum with bells on, which
    -- is still an alarm clock and nothing else. The feet are black.
    alarm = {
        sdf = alarm, rim = red, dark = slate, turns = 0.5, elev = 0.15,
        face = function(x, y, z, colour)
            if y < FOOT_Y + FOOT_R * 0.6 and abs(x) > 1.2 then
                return (colour == blush or colour == red) and slate or ink
            end
            if z > ALARM_T - 0.35 and sqrt(x * x + y * y) < ALARM_R - 0.6 then
                local part = dial(x, y, ALARM_DIAL, 1.6, 2.3)
                if part == "hand" then return ink end
                if part == "dial" then
                    if colour == blush then return paper end
                    if colour == red then return graphite end
                end
            end
            return colour
        end,
    },
    star = { sdf = star, rim = slate, dark = ink, turns = 0.6, elev = 0.12 },
}

--- painting -------------------------------------------------------------------

-- From the screen (x right, y down, z at you) back into the solid's own frame:
-- undo the look from above, then the turn, then the lean.
local function toObject(kind, ca, sa, sx, sy, sz)
    local u, w = -sy, sz
    local ce, se = kind.ce, kind.se
    local y = u * ce + w * se
    local z = -u * se + w * ce
    local x = sx * ca - z * sa
    z = sx * sa + z * ca
    if kind.lean then
        local cl, sl = kind.cl, kind.sl
        local y2 = y * cl - z * sl
        z = y * sl + z * cl
        y = y2
    end
    return x, y, z
end

local function paint(kindName, step)
    local kind = KINDS[kindName]
    if not kind.ce then
        local elev = kind.elev or ELEV
        kind.ce, kind.se = cos(elev), sin(elev)
        if kind.lean then kind.cl, kind.sl = cos(kind.lean), sin(kind.lean) end
    end
    local a = step / STEPS * TAU
    local ca, sa = cos(a), sin(a)
    local sdf, ramp, glint = kind.sdf, RAMP[kindName], GLINT[kindName]

    local function at(sx, sy, sz)
        return sdf(toObject(kind, ca, sa, sx / SIZE, sy / SIZE, sz / SIZE)) * SIZE
    end

    -- First pass: march each pixel's ray in from the front, light what it hits.
    local hit, lit = {}, {}
    for j = -BOX, BOX do
        local row = {}
        hit[j], lit[j] = row, {}
        for i = -BOX, BOX do
            local sx, sy = i + 0.5, j + 0.5
            local z = DEPTH
            local found = false
            for _ = 1, 48 do
                local d = at(sx, sy, z)
                if d < 0.02 then found = true; break end
                z = z - max(d, 0.05)
                if z < -DEPTH then break end
            end
            if found then
                local e = 0.05
                local nx = at(sx + e, sy, z) - at(sx - e, sy, z)
                local ny = at(sx, sy + e, z) - at(sx, sy - e, z)
                local nz = at(sx, sy, z + e) - at(sx, sy, z - e)
                local len = sqrt(nx * nx + ny * ny + nz * nz)
                if len > 0 then nx, ny, nz = nx / len, ny / len, nz / len end
                local light = LX * nx + LY * ny + LZ * nz

                local colour
                for _, band in ipairs(ramp) do
                    if light > band.at then
                        colour = (band[2] and (i + j) % 2 == 0) and band[2] or band[1]
                        break
                    end
                end
                if kind.face then
                    local ox, oy, oz = toObject(kind, ca, sa, sx / SIZE, sy / SIZE, z / SIZE)
                    colour = kind.face(ox, oy, oz, colour)
                end
                if HX * nx + HY * ny + HZ * nz > glint then colour = paper end
                row[i] = colour
                lit[j][i] = light > 0
            end
        end
    end

    -- Second pass: the rim, and runs of one colour along each row.
    local rows, top, bottom, left, right = {}, nil, nil, nil, nil
    for j = -BOX, BOX do
        local row, up, down = hit[j], hit[j - 1] or {}, hit[j + 1] or {}
        local runs, cur, from = {}, nil, nil
        for i = -BOX, BOX + 1 do
            local colour = row[i]
            if colour then
                if not (row[i - 1] and row[i + 1] and up[i] and down[i]) then
                    colour = lit[j][i] and kind.rim or kind.dark
                end
                top, bottom = top or j, j
                left, right = min(left or i, i), max(right or i, i)
            end
            if colour ~= cur then
                if cur then runs[#runs + 1] = { from, i, cur } end
                cur, from = colour, i
            end
        end
        if #runs > 0 then rows[#rows + 1] = { j = j, runs = runs } end
    end

    return { rows = rows, bottom = bottom or 0, width = (right or 0) - (left or 0) + 1 }
end

local cache = {}

-- The picture of a kind at a time, its own turns a second from its own phase.
local function picture(kindName, t)
    local step = floor((t * KINDS[kindName].turns % 1) * STEPS) % STEPS
    local kept = cache[kindName]
    if not kept then
        kept = {}
        cache[kindName] = kept
    end
    local pic = kept[step]
    if not pic then
        pic = paint(kindName, step)
        kept[step] = pic
    end
    return pic
end

--- drawing --------------------------------------------------------------------

-- How high it floats over its shadow: three pixels, and a slow bob of one more
-- each way on top -- whole pixels, so it steps rather than swims.
local HOVER, BOB, BOB_RATE = 3, 1, 2.6

local function lift(t)
    return HOVER + floor(sin(t * BOB_RATE) * BOB + 0.5)
end

-- Where the body's centre goes for a pickup standing at (x, y): (x, y) is where
-- it is touched, and the shadow is struck four below it, where the old sprites'
-- feet were.
local GROUND = 4

local function place(pic, x, y, t)
    return floor(x), floor(y) + GROUND - lift(t) - pic.bottom - 1
end

-- The patch of graphite on the page under it: a flat oval two rows deep, as wide
-- as the body is this frame less a pixel each side, and narrower again the
-- higher it floats -- so a coin edge-on throws a sliver, and the bob reads as
-- height off the paper. Two rows rather than the crowd's one because a thing in
-- the air throws a pool, not a line under its feet, and the pool is what says it
-- is off the ground.
function Trinket.drawShadow(kindName, x, y, t)
    local pic = picture(kindName, t)
    local w = max(pic.width - 2 - 2 * (lift(t) - HOVER + 1), 1)
    local x0, y0 = floor(x) - floor(w / 2), floor(y) + GROUND
    love.graphics.setColor(graphite)
    love.graphics.rectangle("fill", x0, y0, w, 1)
    if w > 4 then love.graphics.rectangle("fill", x0 + 2, y0 + 1, w - 4, 1) end
end

-- The silhouette in whatever colour is set: the blank stamped into the page
-- under it (Overprint.beginSolid), so the ruling stops at its edge.
function Trinket.drawMask(kindName, x, y, t)
    local pic = picture(kindName, t)
    local ox, oy = place(pic, x, y, t)
    for _, row in ipairs(pic.rows) do
        for _, run in ipairs(row.runs) do
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

function Trinket.draw(kindName, x, y, t)
    local pic = picture(kindName, t)
    local ox, oy = place(pic, x, y, t)
    local cur
    for _, row in ipairs(pic.rows) do
        for _, run in ipairs(row.runs) do
            if run[3] ~= cur then
                cur = run[3]
                love.graphics.setColor(cur)
            end
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

return Trinket
