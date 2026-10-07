-- The pickups' bodies (src/pickup.lua): the heart, the ink drop, the diamond and
-- the coin, each a small solid turning on the spot over its own shadow.
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
-- **No bigger than the hero.** Each is nine pixels across at most (the hero's
-- board is 15 by 19): a prize larger than the one who picks it up reads as
-- something to walk round rather than into, and the old sprites' sizes are kept
-- as near as the shapes allow.
--
-- Drawn the eye's way otherwise: eight colours, no alpha, the ramp stepping down
-- through checkered pairs, and a rim one pixel deep round the outside in the
-- colour the kind was always outlined in -- red for health, blue for ink, ink for
-- the coin and slate for the diamond -- so the colour code survives the turn.

local Palette = require("src.palette")

local Trinket = {}

local sqrt, floor, sin, cos, abs, max, min = math.sqrt, math.floor, math.sin,
    math.cos, math.abs, math.max, math.min
local TAU = math.pi * 2

-- How many headings a turn is cut into. Thirty-two is a picture every eleven
-- degrees: at the fastest spin below that is a new picture every 40ms, which on
-- a nine-pixel body is as smooth as the turn can look.
local STEPS = 32

-- Seen from a little above, the piggy bank's way: the top of a thing tipped a
-- little towards you, so the coin turning edge-on is a thin ellipse rather than
-- a line, and the diamond shows its table.
-- The heart is the exception (`elev` on its row): seen from above, its own
-- thickness fills the dip between the lobes, and the dip is half of what makes it
-- a heart.
local ELEV = 0.3

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

-- The box a picture is painted in, about its centre: nine across and nine down
-- with a pixel of slack each way for the rim, and the march's depth.
local BOX = 6
local DEPTH = 8

local paper, graphite, slate, ink = Palette.paper, Palette.graphite, Palette.slate, Palette.ink
local red, blush, blue, sky = Palette.red, Palette.blush, Palette.blue, Palette.sky

--- the solids -----------------------------------------------------------------
-- Each is a distance in its own frame: x across, y up, z through its face, in
-- pixels, centred on the middle of the body.

-- The heart: Inigo Quilez's 2D heart, pushed out into a pillow. A flat heart
-- turning is a playing card; a puffed one is a sweet, which is what it is.
local HEART_S = 7.5     -- the 2D shape is about 1.2 by 1.1; this makes it nine by eight
local HEART_Y = 4.1     -- lifts its point off the bottom so the middle is the middle
local HEART_T, HEART_R = 0.9, 0.8

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
local GIRDLE, GIRDLE_Y = 4.6, 1.2
local TABLE, TABLE_Y = 2.4, 3.0
local POINT_Y = -4.4
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
        local b = (k + 0.5) / FACETS * TAU
        PAVILION[k + 1] = { cos(b) * pr, py, sin(b) * pr, pd }
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
local COIN_R, COIN_T = 4.4, 0.8

local function coin(x, y, z)
    local dr = sqrt(x * x + y * y) - COIN_R
    local dz = abs(z) - COIN_T
    local ox, oz = max(dr, 0), max(dz, 0)
    return min(max(dr, dz), 0) + sqrt(ox * ox + oz * oz)
end

-- The purse's 1, three by five, on the face's own grid.
local FIGURE = { ".#.", "##.", ".#.", ".#.", "###" }

--- the ramps ------------------------------------------------------------------
-- Down the light, brightest first: past `at` a pixel is the first colour, or the
-- two checkered when there are two. The last row catches everything left.

local RAMP = {
    heart = {
        { at = 0.35, blush }, { at = 0.08, blush, red },
        { at = -0.4, red }, { at = -2, red, slate },
    },
    ink = {
        { at = 0.35, sky }, { at = 0.08, sky, blue },
        { at = -0.4, blue }, { at = -2, blue, slate },
    },
    -- Cut from paper, as it always was: like the eye and the ruler body it is
    -- the paper side of the ramp that does the work, and sky is its shade.
    diamond = {
        { at = 0.8, paper }, { at = 0.55, paper, sky },
        { at = 0.25, sky }, { at = -0.1, sky, blue }, { at = -2, blue },
    },
    coin = {
        { at = 0.3, blush }, { at = 0.0, blush, red },
        { at = -0.4, red }, { at = -2, red, slate },
    },
}

-- How fine a highlight is: past this along the half-way vector, paper. A
-- diamond's is wide on purpose, so a whole facet flashes as it comes round.
local GLINT = { heart = 0.96, ink = 0.97, diamond = 0.9, coin = 0.96 }

--- the kinds ------------------------------------------------------------------
-- `turns` is turns a second, `lean` a tilt applied before the turn, and `face`
-- anything painted on top of the ramp, handed the point it hit in its own frame.

local KINDS = {
    heart = { sdf = heart, rim = red, turns = 0.55, elev = 0.05 },
    ink = { sdf = drop, rim = blue, turns = 0.7, lean = DROP_LEAN },
    diamond = { sdf = diamond, rim = slate, turns = 0.4 },
    coin = {
        sdf = coin, rim = ink, turns = 0.8,
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
            return colour == blush and red or colour
        end,
    },
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
        return sdf(toObject(kind, ca, sa, sx, sy, sz))
    end

    -- First pass: march each pixel's ray in from the front, light what it hits.
    local hit = {}
    for j = -BOX, BOX do
        local row = {}
        hit[j] = row
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
                    local ox, oy, oz = toObject(kind, ca, sa, sx, sy, z)
                    colour = kind.face(ox, oy, oz, colour)
                end
                if HX * nx + HY * ny + HZ * nz > glint then colour = paper end
                row[i] = colour
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
                    colour = kind.rim
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

-- How high it floats over its shadow: two pixels, and a slow bob of one more
-- each way on top -- whole pixels, so it steps rather than swims.
local HOVER, BOB, BOB_RATE = 2, 1, 2.6

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

-- The scrap of graphite on the page under it: as wide as the body is this
-- frame, less a pixel each side, and narrower again the higher it floats -- so a
-- coin edge-on throws a sliver, and the bob reads as height off the paper.
function Trinket.drawShadow(kindName, x, y, t)
    local pic = picture(kindName, t)
    local w = max(pic.width - 2 - (lift(t) - HOVER + 1), 1)
    love.graphics.setColor(graphite)
    love.graphics.rectangle("fill", floor(x) - floor(w / 2), floor(y) + GROUND, w, 1)
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
