-- A body built out of simple solids and ray-traced a pixel at a time, every
-- frame it changes: the whistle, the metronome, the stamp, the dictionary and
-- the marble (their models are rows in src/solids.lua).
--
-- These five used to be traced ahead of time (by a Python tracer, art/raytrace.py,
-- since retired) into rings of baked ASCII views -- sixteen headings, and for the
-- three that move, a ring per pose. That bought any shape a distance field could describe, at the price of
-- turning in sixteenths and moving in held frames: the stamp could be stood,
-- reared, leant or squashed and nothing between; the marble could be one of
-- five carvings. This is the piggy bank's method (src/piggy.lua) brought to
-- them: every ray is solved in closed form against a short list of solids, so
-- the body is painted fresh for whatever heading and whatever pose it is in.
--
-- **The camera is the bake's camera.** Orthographic, looking down at the page
-- from `PITCH` above it, a model unit `UNIT` of a pixel, the light fixed in the
-- room at the top left and a little towards you -- the bake's numbers to the
-- digit, so the five come out the size and the colour they always were,
-- and the floor sums the brains line things up by (the stamp's pad in a ledger
-- cell, the dictionary's spine on the ruling) still hold: depth along the
-- floor is foreshortened by the sine of the tilt and height by its cosine.
--
-- **The solids are the ones with a closed answer.** A ray against
--
--   box    a box, as three slabs
--   hull   a convex polyhedron, as a list of planes: a pyramid, a wedge, a box
--          with its edges taken off
--   cone   a solid of revolution whose radius changes linearly along its axis,
--          with flat ends: a cylinder is a cone with one radius
--   ball   a unit sphere, which an affine map makes any ellipsoid at any angle
--
-- is an interval of the ray (in at one face, out at another), solved straight
-- from a plane's sum or a quadratic. A *part* is one of those, optionally cut
-- down to what is inside a second (`within`: the marble's bust inside its block)
-- and with a third taken away (`minus`: the whistle's window, the metronome's
-- panel) -- for convex solids both are a comparison of two intervals. A body
-- is a list of parts, and a ray keeps the nearest.
--
-- **Everything that moves is a map.** Each solid sits in its part's space
-- through its own affine map (`at`); each part can be moved in the body
-- (`move`: the dictionary's board, hinged at the spine); the whole body can be
-- posed (`pose`: the stamp rocking on its heel, squashing on landing); and the
-- heading turns it about its pivot. A ray is taken back through all of those
-- into each solid's own space, where the question is the simple one, and the
-- answer's normal comes back out through the inverse transpose. Nothing is
-- turned at draw time and nothing is baked: the picture is painted for this
-- heading, this pose and this frame.
--
-- **Drawn the way the bake drew.** One ray a pixel, at its middle, so nothing
-- is ever averaged into a ninth colour; diffuse and a tight glint off the room's
-- lamp, a shadow ray back towards it so a knob throws its shadow on the block
-- under it; the colour picked by the model's own `shade` from a ramp of palette
-- keys, the red ramp when it says nothing; creases a step darker where two faces
-- of one material meet at an angle; and ink round the outside and down any step
-- in depth where one part stands in front of another. The picture is worked out
-- into rows of runs, and the blank under it, the hit rim and the body itself all
-- read the same rows.
--
-- **Pictures are kept, and new ones painted a slice at a time.** A picture is a
-- few milliseconds of rays, which a phone running LuaJIT's interpreter would feel
-- every frame. So the heading is drawn to a ninety-sixth of a turn and the pose
-- to the model's steps, a picture is kept under that key (shared by every body of
-- a model, so the library's turntable and the fight paint each once), and one
-- not kept yet is painted in a coroutine a slice a frame while the last finished
-- picture goes on being drawn (`refresh`). 3dmethod.md has the numbers.

local Palette = require("src.palette")

local Solid = {}
Solid.__index = Solid

local sqrt, floor, cos, sin, abs = math.sqrt, math.floor, math.cos, math.sin, math.abs
local max, min = math.max, math.min
local HUGE = math.huge
local TAU = math.pi * 2

-- The bake's camera: looked at from 34 degrees above the page, 0.92 model units
-- to a pixel.
local PITCH = math.rad(34)
local CP, SP = cos(PITCH), sin(PITCH)
local UNIT = 0.92
-- How far back the camera stands: anything further than the biggest body is
-- tall, so every ray starts outside every solid.
local BACK = 200

-- The room's lamp: up, to the left and towards you, fixed whichever way the body
-- is turned. The glint is the half-way vector between it and the eye.
local LX, LY, LZ = -0.5, 0.75, 0.45
do
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local EX, EY, EZ = 0, SP, CP
local HX, HY, HZ = LX + EX, LY + EY, LZ + EZ
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end
-- The ray from the camera, along -z of the camera, in the room.
local DX, DY, DZ = 0, -SP, -CP

-- How turned two neighbouring pixels' normals have to be, within one material,
-- for the step between them to be a crease (the bake's 0.55).
local CREASE = 0.55

local key = Palette.key

--- affine maps -----------------------------------------------------------------

-- Twelve numbers, row-major: the 3x3 and then the shift, for each of x, y, z.
local Affine = {}
Solid.Affine = Affine

function Affine.id() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 } end

function Affine.translate(x, y, z) return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z } end

function Affine.scale(x, y, z) return { x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0 } end

-- A turn of `a` about one of the axes, the right-handed way: about z, +x goes
-- to +y.
function Affine.rotate(axis, a)
    local c, s = cos(a), sin(a)
    if axis == "x" then return { 1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0 } end
    if axis == "y" then return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0 } end
    return { c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0 }
end

-- `p` after `q`: x -> p(q(x)). Any number of them, the last applied first.
function Affine.mul(p, q, ...)
    local r = {}
    for row = 0, 2 do
        local a1, a2, a3, a4 = p[row * 4 + 1], p[row * 4 + 2], p[row * 4 + 3], p[row * 4 + 4]
        for col = 1, 3 do
            r[row * 4 + col] = a1 * q[col] + a2 * q[4 + col] + a3 * q[8 + col]
        end
        r[row * 4 + 4] = a1 * q[4] + a2 * q[8] + a3 * q[12] + a4
    end
    if ... then return Affine.mul(r, ...) end
    return r
end

-- A map done about a point rather than the origin: a hinge, a heel.
function Affine.about(m, x, y, z)
    return Affine.mul(Affine.translate(x, y, z), m, Affine.translate(-x, -y, -z))
end

function Affine.inv(m)
    local a, b, c, tx, e, f, g, ty, i, j, k, tz =
        m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]
    local c11, c12, c13 = f * k - g * j, -(e * k - g * i), e * j - f * i
    local det = a * c11 + b * c12 + c * c13
    local d = 1 / det
    local r1, r2, r3 = c11 * d, -(b * k - c * j) * d, (b * g - c * f) * d
    local r5, r6, r7 = c12 * d, (a * k - c * i) * d, -(a * g - c * e) * d
    local r9, r10, r11 = c13 * d, -(a * j - b * i) * d, (a * f - b * e) * d
    return {
        r1, r2, r3, -(r1 * tx + r2 * ty + r3 * tz),
        r5, r6, r7, -(r5 * tx + r6 * ty + r7 * tz),
        r9, r10, r11, -(r9 * tx + r10 * ty + r11 * tz),
    }
end

function Affine.apply(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4],
        m[5] * x + m[6] * y + m[7] * z + m[8],
        m[9] * x + m[10] * y + m[11] * z + m[12]
end

--- the solids --------------------------------------------------------------------

-- Each is a table: `kind`, its own numbers, `at` (its space to the part's), and
-- a box round it in its own space (`lo`, `hi`), which is what decides which
-- pixels ask it anything: its eight corners are put on the screen each raster.

-- A convex polyhedron: planes as {nx, ny, nz, w}, inside where n . p <= w.
-- `bound` is the box round it, {x0, y0, z0, x1, y1, z1}; a hull that is only
-- ever cut or clipped by (`within`, `minus`) is never bounded and needs none.
function Solid.hull(planes, bound)
    local flat = {}
    for _, p in ipairs(planes) do
        local n = sqrt(p[1] ^ 2 + p[2] ^ 2 + p[3] ^ 2)
        flat[#flat + 1] = p[1] / n
        flat[#flat + 1] = p[2] / n
        flat[#flat + 1] = p[3] / n
        flat[#flat + 1] = p[4] / n
    end
    bound = bound or { 0, 0, 0, 0, 0, 0 }
    return { kind = "hull", planes = flat, at = Affine.id(),
             lo = { bound[1], bound[2], bound[3] }, hi = { bound[4], bound[5], bound[6] },
             round = sqrt((bound[4] - bound[1]) ^ 2 + (bound[5] - bound[2]) ^ 2
                 + (bound[6] - bound[3]) ^ 2) / 2 }
end

-- A box: middle and half-sizes. Asked as three slabs rather than six planes,
-- which is most of the cost of a body made of boxes.
function Solid.box(cx, cy, cz, hx, hy, hz)
    return { kind = "box", at = Affine.id(),
             lo = { cx - hx, cy - hy, cz - hz }, hi = { cx + hx, cy + hy, cz + hz },
             round = sqrt(hx * hx + hy * hy + hz * hz) }
end

-- A box with its edges taken off at forty five degrees, `bevel` in from where
-- they were: the bake's rounded boxes, as near as flat faces get. A box is
-- quick to ask and a bevelled one is eighteen planes, so only the big ones
-- whose corners are seen get it.
function Solid.bevelled(cx, cy, cz, hx, hy, hz, bevel)
    local planes = {
        { 1, 0, 0, cx + hx }, { -1, 0, 0, -(cx - hx) },
        { 0, 1, 0, cy + hy }, { 0, -1, 0, -(cy - hy) },
        { 0, 0, 1, cz + hz }, { 0, 0, -1, -(cz - hz) },
    }
    local cut = bevel * (2 - sqrt(2))
    local function edge(ax, ay, az, bx, by, bz, ha, hb)
        -- n = a + b (two unit axes), through the box's middle shifted out.
        local w = (ax + bx) * cx + (ay + by) * cy + (az + bz) * cz + ha + hb - cut
        planes[#planes + 1] = { ax + bx, ay + by, az + bz, w }
    end
    for _, sa in ipairs({ 1, -1 }) do
        for _, sb in ipairs({ 1, -1 }) do
            edge(sa, 0, 0, 0, sb, 0, hx, hy)
            edge(sa, 0, 0, 0, 0, sb, hx, hz)
            edge(0, sa, 0, 0, 0, sb, hy, hz)
        end
    end
    -- Solid.hull divides each plane by its normal's length, which is what turns
    -- `w` above (said along a + b) into a distance along the unit normal.
    return Solid.hull(planes, { cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz })
end

-- Which way a local y axis has to be turned to lie along each of the three.
local AXES = {
    x = Affine.rotate("z", -math.pi / 2),
    y = Affine.id(),
    z = Affine.rotate("x", math.pi / 2),
}

-- A cone along `axis` through (cx, cy, cz): radius `r0` at `a0` along the axis
-- from there and `r1` at `a1`, flat at both ends. A cylinder is r0 == r1.
function Solid.cone(axis, cx, cy, cz, a0, a1, r0, r1)
    local at = Affine.mul(Affine.translate(cx, cy, cz), AXES[axis])
    local r = max(r0, r1)
    return { kind = "cone", a0 = a0, a1 = a1, r0 = r0, r1 = r1, at = at,
             lo = { -r, a0, -r }, hi = { r, a1, r }, round = sqrt(r * r + ((a1 - a0) / 2) ^ 2) }
end

function Solid.cyl(axis, cx, cy, cz, half, r)
    return Solid.cone(axis, cx, cy, cz, -half, half, r, r)
end

-- An ellipsoid: middle and three radii, turned by `turn` (an affine with no
-- shift) if it lies at an angle.
function Solid.ell(cx, cy, cz, rx, ry, rz, turn)
    local at = Affine.scale(rx, ry, rz)
    if turn then at = Affine.mul(turn, at) end
    at = Affine.mul(Affine.translate(cx, cy, cz), at)
    return { kind = "ball", at = at, lo = { -1, -1, -1 }, hi = { 1, 1, 1 }, round = 1 }
end

-- A capsule-ish lump from (ax, ay, az) to (bx, by, bz), `r` round: an ellipsoid
-- along the segment, as long as the capsule and as thick.
function Solid.lump(ax, ay, az, bx, by, bz, r)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / len, dy / len, dz / len
    -- Any two directions square to the segment.
    local ux, uy, uz
    if abs(dy) < 0.9 then ux, uy, uz = 0, 1, 0 else ux, uy, uz = 1, 0, 0 end
    local px, py, pz = uy * dz - uz * dy, uz * dx - ux * dz, ux * dy - uy * dx
    local pn = sqrt(px * px + py * py + pz * pz)
    px, py, pz = px / pn, py / pn, pz / pn
    local qx, qy, qz = dy * pz - dz * py, dz * px - dx * pz, dx * py - dy * px
    local turn = { dx, px, qx, 0, dy, py, qy, 0, dz, pz, qz, 0 }
    return Solid.ell((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, len / 2 + r, r, r, turn)
end

-- A part: a solid, what it is made of (handed to the model's `shade`), and
-- optionally `within` (kept only inside this) and `minus` (a list of solids
-- taken out of it),
-- `move` (where the part is moved to in the body) and any other fields the
-- model's shade wants to read off it.
function Solid.part(solid, mat, opts)
    local p = opts or {}
    p.solid, p.mat = solid, mat
    return p
end

--- one ray against one solid --------------------------------------------------------

-- Each answers whether the ray (o + t d) goes through it, in its own space, and
-- leaves the interval inside it and the normals where the ray goes in and comes
-- out in the eight values below rather than returning them: the hot loop is
-- written for LuaJIT, which gives up compiling a trace that assigns several
-- values at once (the red pen's lesson, src/redpen.lua), so nothing here does.
local T0, T1, AX, AY, AZ, BX, BY, BZ = 0, 0, 0, 0, 0, 0, 0, 0

local function hull(s, ox, oy, oz, dx, dy, dz)
    local pl = s.planes
    local t0 = -HUGE
    local t1 = HUGE
    local ak, bk = 0, 0
    for k = 1, #pl, 4 do
        local nx = pl[k]
        local ny = pl[k + 1]
        local nz = pl[k + 2]
        local den = nx * dx + ny * dy + nz * dz
        local num = pl[k + 3] - (nx * ox + ny * oy + nz * oz)
        if den < -1e-12 then
            local t = num / den
            if t > t0 then
                t0 = t
                ak = k
            end
        elseif den > 1e-12 then
            local t = num / den
            if t < t1 then
                t1 = t
                bk = k
            end
        elseif num < 0 then
            return false
        end
        if t0 >= t1 then return false end
    end
    T0 = t0
    T1 = t1
    if ak > 0 then
        AX = pl[ak]
        AY = pl[ak + 1]
        AZ = pl[ak + 2]
    end
    if bk > 0 then
        BX = pl[bk]
        BY = pl[bk + 1]
        BZ = pl[bk + 2]
    end
    return true
end

local function box(s, ox, oy, oz, dx, dy, dz)
    local lo, hi = s.lo, s.hi
    local t0 = -HUGE
    local t1 = HUGE
    local ain, aout = 0, 0
    -- x
    if dx > 1e-12 or dx < -1e-12 then
        local ta = (lo[1] - ox) / dx
        local tb = (hi[1] - ox) / dx
        if ta > tb then
            local swap = ta
            ta = tb
            tb = swap
        end
        if ta > t0 then
            t0 = ta
            ain = dx > 0 and -1 or 1
        end
        if tb < t1 then
            t1 = tb
            aout = dx > 0 and 1 or -1
        end
    elseif ox < lo[1] or ox > hi[1] then
        return false
    end
    -- y
    if dy > 1e-12 or dy < -1e-12 then
        local ta = (lo[2] - oy) / dy
        local tb = (hi[2] - oy) / dy
        if ta > tb then
            local swap = ta
            ta = tb
            tb = swap
        end
        if ta > t0 then
            t0 = ta
            ain = dy > 0 and -2 or 2
        end
        if tb < t1 then
            t1 = tb
            aout = dy > 0 and 2 or -2
        end
    elseif oy < lo[2] or oy > hi[2] then
        return false
    end
    if t0 >= t1 then return false end
    -- z
    if dz > 1e-12 or dz < -1e-12 then
        local ta = (lo[3] - oz) / dz
        local tb = (hi[3] - oz) / dz
        if ta > tb then
            local swap = ta
            ta = tb
            tb = swap
        end
        if ta > t0 then
            t0 = ta
            ain = dz > 0 and -3 or 3
        end
        if tb < t1 then
            t1 = tb
            aout = dz > 0 and 3 or -3
        end
    elseif oz < lo[3] or oz > hi[3] then
        return false
    end
    if t0 >= t1 then return false end
    T0 = t0
    T1 = t1
    -- The faces gone in and out at, as an axis with a sign.
    AX = (ain == 1 and 1 or ain == -1 and -1 or 0)
    AY = (ain == 2 and 1 or ain == -2 and -1 or 0)
    AZ = (ain == 3 and 1 or ain == -3 and -1 or 0)
    BX = (aout == 1 and 1 or aout == -1 and -1 or 0)
    BY = (aout == 2 and 1 or aout == -2 and -1 or 0)
    BZ = (aout == 3 and 1 or aout == -3 and -1 or 0)
    return true
end

local function ball(s, ox, oy, oz, dx, dy, dz)
    local a = dx * dx + dy * dy + dz * dz
    local b = ox * dx + oy * dy + oz * dz
    local c = ox * ox + oy * oy + oz * oz - 1
    local disc = b * b - a * c
    if disc <= 0 then return false end
    local sq = sqrt(disc)
    local t0 = (-b - sq) / a
    local t1 = (-b + sq) / a
    T0 = t0
    T1 = t1
    AX = ox + t0 * dx
    AY = oy + t0 * dy
    AZ = oz + t0 * dz
    BX = ox + t1 * dx
    BY = oy + t1 * dy
    BZ = oz + t1 * dz
    return true
end

local function cone(s, ox, oy, oz, dx, dy, dz)
    local a0 = s.a0
    local a1 = s.a1
    local m = s.slope
    local k = s.base
    -- The slab between the ends first.
    local t0 = -HUGE
    local t1 = HUGE
    local in0 = 0
    if abs(dy) < 1e-12 then
        if oy < a0 or oy > a1 then return false end
    elseif dy > 0 then
        t0 = (a0 - oy) / dy
        t1 = (a1 - oy) / dy
        in0 = -1
    else
        t0 = (a1 - oy) / dy
        t1 = (a0 - oy) / dy
        in0 = 1
    end
    -- Then the side: x^2 + z^2 <= (k + m y)^2 along the ray, a quadratic in t.
    -- Inside the slab the radius is never negative, so only the one nappe is
    -- in it and what is left is one interval.
    local ry = k + m * oy
    local rd = m * dy
    local qa = dx * dx + dz * dz - rd * rd
    local qb = ox * dx + oz * dz - ry * rd
    local qc = ox * ox + oz * oz - ry * ry
    local s0 = -HUGE
    local s1 = HUGE
    if abs(qa) < 1e-12 then
        if abs(qb) < 1e-12 then
            if qc > 0 then return false end
        elseif qb > 0 then
            s1 = -qc / (2 * qb)
        else
            s0 = -qc / (2 * qb)
        end
    else
        local disc = qb * qb - qa * qc
        if disc < 0 then
            if qa > 0 then return false end
        else
            local sq = sqrt(disc)
            local ra = (-qb - sq) / qa
            local rb = (-qb + sq) / qa
            if ra > rb then
                local swap = ra
                ra = rb
                rb = swap
            end
            if qa > 0 then
                s0 = ra
                s1 = rb
            elseif min(t1, ra) > t0 then
                s1 = ra
            else
                s0 = rb
            end
        end
    end
    local e0 = max(t0, s0)
    local e1 = min(t1, s1)
    if e0 >= e1 then return false end
    T0 = e0
    T1 = e1
    if s0 > t0 then
        local y = oy + e0 * dy
        AX = ox + e0 * dx
        AY = -m * (k + m * y)
        AZ = oz + e0 * dz
    else
        AX = 0
        AY = in0
        AZ = 0
    end
    if s1 < t1 then
        local y = oy + e1 * dy
        BX = ox + e1 * dx
        BY = -m * (k + m * y)
        BZ = oz + e1 * dz
    else
        BX = 0
        BY = -in0
        BZ = 0
    end
    return true
end

local SHAPES = { hull = hull, box = box, ball = ball, cone = cone }

-- Ready to be asked: its map from the room, and both of the directions it will
-- be asked along, in its own space.
local function prepare(s, inv)
    s.inv = Affine.mul(Affine.inv(s.at), inv)
    s.shape = SHAPES[s.kind]
    if s.kind == "cone" then
        s.slope = (s.r1 - s.r0) / (s.a1 - s.a0)
        s.base = s.r0 - s.slope * s.a0
    end
    local m = s.inv
    s.dx = m[1] * DX + m[2] * DY + m[3] * DZ
    s.dy = m[5] * DX + m[6] * DY + m[7] * DZ
    s.dz = m[9] * DX + m[10] * DY + m[11] * DZ
    s.lx = m[1] * LX + m[2] * LY + m[3] * LZ
    s.ly = m[5] * LX + m[6] * LY + m[7] * LZ
    s.lz = m[9] * LX + m[10] * LY + m[11] * LZ
    s.memo = nil
end

-- Which ray is being asked about, counted, so a solid shared by several parts
-- (`shared`: the marble's block, inside which every piece of the bust is kept)
-- is solved once a ray rather than once a part.
local ray = 0

-- A room ray against a solid: its origin taken into the solid's space by its
-- `inv` (worked out per raster), along a direction worked out once a raster too
-- -- every ray from the camera goes the same way, and so does every ray back to
-- the lamp (`lamp`) -- and its normals brought back out into the room by the
-- transpose of the same map. Leaves t in and out and the room normals at both in
-- the eight values above.
local function solve(s, ox, oy, oz, lamp)
    if s.shared and s.memo == ray then
        if not s.hit then return false end
        T0 = s.m0
        T1 = s.m1
        AX = s.ma
        AY = s.mb
        AZ = s.mc
        BX = s.md
        BY = s.me
        BZ = s.mf
        return true
    end
    local m = s.inv
    local lx = m[1] * ox + m[2] * oy + m[3] * oz + m[4]
    local ly = m[5] * ox + m[6] * oy + m[7] * oz + m[8]
    local lz = m[9] * ox + m[10] * oy + m[11] * oz + m[12]
    local hit
    if lamp then
        hit = s.shape(s, lx, ly, lz, s.lx, s.ly, s.lz)
    else
        hit = s.shape(s, lx, ly, lz, s.dx, s.dy, s.dz)
    end
    if hit then
        local ax = AX
        local ay = AY
        local az = AZ
        AX = m[1] * ax + m[5] * ay + m[9] * az
        AY = m[2] * ax + m[6] * ay + m[10] * az
        AZ = m[3] * ax + m[7] * ay + m[11] * az
        local bx = BX
        local by = BY
        local bz = BZ
        BX = m[1] * bx + m[5] * by + m[9] * bz
        BY = m[2] * bx + m[6] * by + m[10] * bz
        BZ = m[3] * bx + m[7] * by + m[11] * bz
    end
    if s.shared then
        s.memo = ray
        s.hit = hit
        s.m0 = T0
        s.m1 = T1
        s.ma = AX
        s.mb = AY
        s.mc = AZ
        s.md = BX
        s.me = BY
        s.mf = BZ
    end
    return hit
end

-- A room ray against a part, from `tmin` on: where it first goes into the part
-- -- the solid, cut down to `within`, with each of `minus` taken out. Leaves the
-- distance in T0 and the room normal there in AX, AY, AZ, and answers whether
-- it hit and whether that surface is the wall of a cut.
local function enter(p, ox, oy, oz, lamp, tmin)
    if not solve(p.solid, ox, oy, oz, lamp) then return false end
    local t0 = T0
    local t1 = T1
    local nx = AX
    local ny = AY
    local nz = AZ
    local w = p.within
    local face = false
    if w then
        if not solve(w, ox, oy, oz, lamp) then return false end
        if T0 > t0 then
            t0 = T0
            nx = AX
            ny = AY
            nz = AZ
            face = true
        end
        if T1 < t1 then t1 = T1 end
        if t0 >= t1 then return false end
    end
    if t1 <= tmin then return false end
    if t0 < tmin then t0 = tmin end
    -- Each cut the ray goes in at is stepped through to its far wall, and the
    -- cuts asked again from there: two sockets side by side are two cuts.
    local cut = false
    local cuts = p.minus
    if cuts then
        local moved = true
        while moved do
            moved = false
            for k = 1, #cuts do
                if solve(cuts[k], ox, oy, oz, lamp) and T0 <= t0 and T1 > t0 then
                    if T1 >= t1 then return false end
                    face = false
                    t0 = T1
                    nx = -BX
                    ny = -BY
                    nz = -BZ
                    cut = true
                    moved = true
                end
            end
        end
    end
    T0 = t0
    AX = nx
    AY = ny
    AZ = nz
    return true, cut, face
end

-- How long a frame a body may spend painting a picture it has not kept, in
-- seconds. A picture is a few milliseconds of rays; one painted in a single
-- frame whenever a pose or a heading is new would be a hitch every time, so it
-- is painted a slice a frame (in a coroutine, `pause` handing the frame back
-- once the slice is spent) while the last picture finished goes on being drawn.
-- A heading or a pose shown a frame or two late reads as nothing at all. A body
-- with nothing else on its screen (the library's turntable) is given more
-- (`slice` on the body).
local SLICE = 0.0015
local clock = (love and love.timer and love.timer.getTime) or os.clock
-- Set only while a slice is being run, so a picture painted all at once (the
-- first a body shows) never tries to yield.
local deadline = HUGE

local function pause()
    if clock() > deadline then coroutine.yield() end
end

-- How much a map can stretch a length, at most (near enough: its longest
-- column).
local function stretch(m)
    return max(sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2), sqrt(m[2] ^ 2 + m[6] ^ 2 + m[10] ^ 2),
        sqrt(m[3] ^ 2 + m[7] ^ 2 + m[11] ^ 2))
end

-- Where a solid can be on the screen, through `m` (its space to the room): the
-- rectangle of pixels its box's eight corners land in, the circle of pixels its
-- bounding sphere does -- each is tighter than the other for some shape, so a
-- pixel is asked only inside both -- and the nearest any of it can be along a
-- camera ray. With `sphere`, the sphere is kept for the rays back to the lamp.
local function bound(p, s, m, sphere)
    local lo, hi = s.lo, s.hi
    local i0, i1, j0, j1, near = HUGE, -HUGE, HUGE, -HUGE, HUGE
    for c = 0, 7 do
        local x = c % 2 == 0 and lo[1] or hi[1]
        local y = floor(c / 2) % 2 == 0 and lo[2] or hi[2]
        local z = floor(c / 4) == 0 and lo[3] or hi[3]
        local rx, ry, rz = Affine.apply(m, x, y, z)
        local i, j = rx / UNIT, -(ry * CP - rz * SP) / UNIT
        i0, i1 = min(i0, i), max(i1, i)
        j0, j1 = min(j0, j), max(j1, j)
        near = min(near, BACK - (ry * SP + rz * CP))
    end
    local cx, cy, cz = Affine.apply(m, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
    local r = s.round * stretch(m)
    local si, sj = cx / UNIT, -(cy * CP - cz * SP) / UNIT
    local rp = r / UNIT + 1
    p.pi0, p.pi1 = max(floor(i0), floor(si - rp)), min(floor(i1) + 1, floor(si + rp) + 1)
    p.pj0, p.pj1 = max(floor(j0), floor(sj - rp)), min(floor(j1) + 1, floor(sj + rp) + 1)
    p.near = max(near, BACK - (cy * SP + cz * CP) - r) - 0.01
    p.si, p.sj, p.sr2 = si, sj, rp * rp
    if sphere then p.rx, p.ry, p.rz, p.rad = cx, cy, cz, r end
end

-- One part's depths, over the pixels its bound covers, into the picture's
-- buffers wherever it is nearer than what is there. Its own function, and a
-- small one, because LuaJIT compiles a loop by what is live in it: the same work
-- inside the raster, with everything that function has in hand, gave up.
--
-- A pixel whose nearest is the face of a `within` itself (the marble's block)
-- is marked with it in `flat`: nothing else kept inside the same thing can be
-- nearer than its face, so they need not ask.
local function depths(p, i0, i1, j0, j1, width, zd, owner, nxs, nys, nzs, cuts, flat)
    local w = p.within or false
    local near = p.near
    local si, sj, sr2 = p.si, p.sj, p.sr2
    local pj0 = max(j0, p.pj0)
    local pj1 = min(j1, p.pj1)
    local pi0 = max(i0, p.pi0)
    local pi1 = min(i1, p.pi1)
    for j = pj0, pj1 do
        if (j - pj0) % 8 == 7 then pause() end
        local base = (j - j0) * width - i0 + 1
        local cy = -j * UNIT
        local oy = cy * CP + BACK * SP
        local oz = -cy * SP + BACK * CP
        local ej = j - sj
        ej = ej * ej
        for i = pi0, pi1 do
            local idx = base + i
            local was = zd[idx]
            local ei = i - si
            if near < was and ei * ei + ej <= sr2 and (not w or flat[idx] ~= w) then
                ray = ray + 1
                local hit, cut, face = enter(p, i * UNIT, oy, oz, false, -HUGE)
                if hit and T0 < was then
                    zd[idx] = T0
                    owner[idx] = p
                    nxs[idx] = AX
                    nys[idx] = AY
                    nzs[idx] = AZ
                    cuts[idx] = cut
                    flat[idx] = face and w
                end
            end
        end
    end
end

-- Whether anything other than `self` stands between a point and the lamp.
local function shadowed(parts, self, sx, sy, sz)
    ray = ray + 1
    for k = 1, #parts do
        local p = parts[k]
        if p ~= self then
            -- The sphere round the part first: most miss.
            local wx = p.rx - sx
            local wy = p.ry - sy
            local wz = p.rz - sz
            local along = wx * LX + wy * LY + wz * LZ
            local rad = p.rad
            if along > -rad and wx * wx + wy * wy + wz * wz - along * along <= rad * rad
                and enter(p, sx, sy, sz, true, 0.2) and T0 < 40 then
                return true
            end
        end
    end
    return false
end

local paint

--- the body ----------------------------------------------------------------------

-- How finely the heading is drawn: a ninety-sixth of a turn, under four
-- degrees, which at the far end of the whistle is a pixel and a half a step --
-- a turn, where the bake's sixteenths were six pixels a step -- and few enough
-- pictures that a body turning to follow you soon has all of them.
local HEADINGS = 96

-- How many pictures each model keeps: every heading of its commonest pose and
-- a good few of the others. Shared by every body of a model, so the library's
-- turntable and the fight paint the same ones once.
local KEEP = 160

-- `model` is a row of src/solids.lua.
function Solid.new(model)
    local self = setmetatable({
        model = model,
        -- Which way its front faces on the page (radians, the way atan2 is on the
        -- screen).
        yaw = model.yaw or math.pi * 0.5,
        -- The pose the brain has it in, and the numbers the model makes of it:
        -- where they are now and where they are going.
        poseName = nil, p = {}, want = {},
        ground = model.ground,
        hidden = false,
        -- The picture up, and the one being painted (`refresh`).
        cache = nil, job = nil,
    }, Solid)
    for k, v in pairs(model.rest or {}) do
        self.p[k] = v
        self.want[k] = v
    end
    if not model.kept then model.kept = { list = {}, at = 1 } end
    return self
end

-- Turned towards heading `a` at `rate` radians a second (at once when there is
-- no rate).
function Solid:face(a, rate, dt)
    local d = (a - self.yaw + math.pi) % TAU - math.pi
    if abs(d) < 1e-4 then return end
    if not rate or abs(d) <= rate * dt then
        self.yaw = a
    else
        self.yaw = self.yaw + (d > 0 and rate or -rate) * dt
    end
end

-- Turned by `a`, for the turntable.
function Solid:spin(a)
    self.yaw = (self.yaw + a) % TAU
end

-- A pose by name (the model's `poses`), for the numbers to ease towards.
function Solid:pose(name)
    if name == self.poseName then return end
    self.poseName = name
    local row = self.model.poses and self.model.poses[name or self.model.first]
    if row then
        for k, v in pairs(row) do self.want[k] = v end
    end
end

-- One of the model's numbers set straight, for a brain that drives it rather
-- than naming a pose (the marble's carving): eased towards like any other.
function Solid:set(k, v)
    self.want[k] = v
end

-- One frame: every number eases towards where it is going, at the rate the
-- model gives it (`ease`, in its own units a second), or snaps.
function Solid:update(dt)
    if dt <= 0 then return end
    local ease = self.model.ease or {}
    for k, v in pairs(self.want) do
        local cur = self.p[k]
        if cur ~= v then
            local rate = ease[k]
            if not rate or not cur then
                cur = v
            else
                local step = v - cur
                local most = rate * dt
                if abs(step) <= most then cur = v else cur = cur + (step > 0 and most or -most) end
            end
            self.p[k] = cur
        end
    end
    self:refresh()
end

function Solid:shadowScale()
    return 1
end

--- where things are ------------------------------------------------------------------

-- The picture actually painted: the heading to a ninety-sixth of a turn and every
-- number to the model's `steps`, so a body that keeps coming back to the same
-- heading and the same pose -- which is most of what a body does -- is drawn
-- from a picture already painted. The key names it.
function Solid:snap()
    local model = self.model
    local turn = floor(self.yaw / TAU * HEADINGS + 0.5) % HEADINGS
    local q = {}
    local key = {}
    for _, k in ipairs(model.params or {}) do
        local step = model.steps and model.steps[k] or 0.01
        local n = floor((self.p[k] or 0) / step + 0.5)
        q[k] = n * step
        key[#key + 1] = n
    end
    local pose = table.concat(key, ",")
    return turn * TAU / HEADINGS, q, turn .. ";" .. pose, turn, pose
end

-- Model to room: the pose, then the pivot taken off and the heading turned on.
-- A heading h points the model's front (-x) along (cos h, sin h) on the page,
-- down the page being towards the camera.
local function frameOf(model, yaw, q)
    local pose = model.pose and model.pose(q) or Affine.id()
    local pv = model.pivot
    local a = yaw + math.pi
    local c, s = cos(a), sin(a)
    local turn = { c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0 }
    return Affine.mul(turn, Affine.translate(-pv[1], -pv[2], -pv[3]), pose)
end

-- A point in the model's rest space, out on the screen as the picture being
-- drawn has it: pixels from the origin (to the right and down), and how far it
-- is from the camera along the ray -- the same distance the picture's depths
-- are in.
function Solid:project(x, y, z)
    local rx, ry, rz = Affine.apply(self:raster().frame, x, y, z)
    local cy = ry * CP - rz * SP
    local cz = ry * SP + rz * CP
    return rx / UNIT, -cy / UNIT, BACK - cz
end

-- The heading the picture being drawn was painted at.
function Solid:heading()
    return self:raster().yaw
end

--- drawing -----------------------------------------------------------------------------

-- A picture painted, kept: a ring of KEEP slots, the oldest let go.
local function keep(kept, key, c)
    c.key = key
    if kept[key] then return end
    local old = kept.list[kept.at]
    if old then kept[old] = nil end
    kept.list[kept.at] = key
    kept.at = kept.at % KEEP + 1
    kept[key] = c
end

-- How many headings ahead of the one shown a turning body paints while it has
-- nothing else to paint.
local AHEAD = 4

-- Up: a picture becomes the one shown. Counted, so a picture that finishes
-- painting after something newer has gone up is kept but not shown -- shown, it
-- would put the body back where it was a moment ago, a flick backwards.
local function show(self, c)
    self.cache = c
    self.shown = (self.shown or 0) + 1
end

-- Once a frame (from `update`): the picture for this heading and pose, if the
-- model has it, or a slice more of painting it. With the one wanted already up,
-- the slice goes on the headings the body is turning towards, so a body turning
-- steadily -- the library's turntable, a boss coming round to you -- finds the
-- next picture painted when it gets there rather than waiting for it.
function Solid:refresh()
    local yaw, q, key, turn, pose = self:snap()
    -- Which way it is turning, off the last heading it moved from.
    if self.turn and turn ~= self.turn then
        self.dir = ((turn - self.turn) % HEADINGS) < HEADINGS / 2 and 1 or -1
    end
    self.turn = turn
    local kept = self.model.kept
    local want = not (self.cache and self.cache.key == key)
    if want and kept[key] then
        show(self, kept[key])
        want = false
    end

    local job = self.job
    if not job then
        local k, y = key, yaw
        if not want then
            -- Nothing needed now: the first heading ahead not painted yet.
            k = nil
            if self.dir then
                for n = 1, AHEAD do
                    local t = (turn + n * self.dir) % HEADINGS
                    if not kept[t .. ";" .. pose] then
                        k, y = t .. ";" .. pose, t * TAU / HEADINGS
                        break
                    end
                end
            end
            if not k then return end
        end
        local model = self.model
        job = { key = k, shown = self.shown,
                co = coroutine.create(function() return paint(model, y, q) end) }
        self.job = job
    end
    deadline = clock() + (self.slice or Solid.slice or SLICE)
    local ok, c = coroutine.resume(job.co)
    deadline = HUGE
    if not ok then error(c) end
    if coroutine.status(job.co) == "dead" then
        keep(kept, job.key, c)
        self.job = nil
        -- Up if it is what is wanted now, or nearer to now than what is up;
        -- kept and left alone if anything has gone up since it was started.
        if job.key == key or (want and job.shown == self.shown) then show(self, c) end
    end
end

-- Whether the picture up is the one for where the body is now: what a turntable
-- waits on before it turns any further.
function Solid:ready()
    local _, _, key = self:snap()
    return self.cache ~= nil and self.cache.key == key
end

-- The picture to draw, as rows of runs relative to the origin: the last one
-- finished -- or, the first time it is asked, this one, painted now.
function Solid:raster()
    if self.cache then return self.cache end
    local yaw, q, key = self:snap()
    local kept = self.model.kept
    local c = kept[key]
    if not c then
        c = paint(self.model, yaw, q)
        keep(kept, key, c)
    end
    show(self, c)
    return c
end

-- A picture painted: the model at heading `yaw` with its numbers at `q`.
paint = function(model, yaw, q)
    local parts = model.build(q)
    local frame = frameOf(model, yaw, q)

    -- Every solid's map from the room back into its own space, and every part's
    -- into the part's (for `shade`); and where each part's bound is on the
    -- screen, so a pixel only asks the parts it could be on.
    local i0, i1, j0, j1 = HUGE, -HUGE, HUGE, -HUGE
    for _, p in ipairs(parts) do
        local fwd = p.move and Affine.mul(frame, p.move) or frame
        p.inv = Affine.inv(fwd)
        prepare(p.solid, p.inv)
        if p.within then prepare(p.within, p.inv) end
        for _, c in ipairs(p.minus or {}) do prepare(c, p.inv) end
        bound(p, p.solid, Affine.mul(fwd, p.solid.at), true)
        if p.within and p.within.hi[1] > p.within.lo[1] then
            -- Kept inside something smaller than itself (the marble's grown bust
            -- in its block): only the pixels both cover.
            local w = p.within
            local si0, si1, sj0, sj1, near = p.pi0, p.pi1, p.pj0, p.pj1, p.near
            local si, sj, sr2 = p.si, p.sj, p.sr2
            bound(p, w, Affine.mul(fwd, w.at))
            p.pi0, p.pi1 = max(si0, p.pi0), min(si1, p.pi1)
            p.pj0, p.pj1 = max(sj0, p.pj0), min(sj1, p.pj1)
            p.near = max(near, p.near)
            p.si, p.sj, p.sr2 = si, sj, sr2
        end
        i0, i1 = min(i0, p.pi0), max(i1, p.pi1)
        j0, j1 = min(j0, p.pj0), max(j1, p.pj1)
    end
    -- Nearest first, so what is behind is mostly not asked at all.
    local order = {}
    for k, p in ipairs(parts) do order[k] = p end
    table.sort(order, function(a, b) return a.near < b.near end)
    -- What can throw a shadow: the parts the model says can (`casts`), or
    -- every part when it says none can't.
    local casters = {}
    for _, p in ipairs(parts) do
        if p.casts or (p.casts == nil and not model.casters) then casters[#casters + 1] = p end
    end
    if i0 > i1 then return { rows = {}, frame = frame, yaw = yaw } end
    local width = i1 - i0 + 1

    local shade = model.shade
    local shadows = model.shadows ~= false
    local np = #parts
    -- Per pixel: colour key, depth, normal and material, in flat arrays.
    local ck, zd, nxs, nys, nzs, cuts, owner = {}, {}, {}, {}, {}, {}, {}
    -- Filled in order first, so they are arrays and not hashes.
    local flat = {}
    for idx = 1, width * (j1 - j0 + 1) do
        zd[idx] = HUGE
        owner[idx] = false
        ck[idx] = false
        flat[idx] = false
    end

    -- First the depths, part by part over the pixels its bound covers, keeping
    -- the nearest; then the light on whatever is nearest at each pixel.
    for k = 1, np do
        depths(order[k], i0, i1, j0, j1, width, zd, owner, nxs, nys, nzs, cuts, flat)
        pause()
    end
    -- Then the light on whatever is nearest at each pixel, and its colour.
    local params = q
    for j = j0, j1 do
        if (j - j0) % 8 == 7 then pause() end
        local base = (j - j0) * width - i0 + 1
        local cy = -j * UNIT
        local oy = cy * CP + BACK * SP
        local oz = -cy * SP + BACK * CP
        for i = i0, i1 do
            local idx = base + i
            local best = owner[idx]
            if best then
                local bestT = zd[idx]
                local bx = nxs[idx]
                local by = nys[idx]
                local bz = nzs[idx]
                local n = sqrt(bx * bx + by * by + bz * bz)
                bx = bx / n
                by = by / n
                bz = bz / n
                local px = i * UNIT + bestT * DX
                local py = oy + bestT * DY
                local pz = oz + bestT * DZ
                local diff = max(0, bx * LX + by * LY + bz * LZ)
                -- Back towards the lamp from just off the surface: anything in
                -- the way is a shadow. Not the part that was hit -- they are
                -- convex, near enough, and cannot shade themselves.
                if shadows and diff > 0
                    and shadowed(casters, best, px + bx * 0.3, py + by * 0.3, pz + bz * 0.3) then
                    diff = diff * 0.35
                end
                local spec = max(0, bx * HX + by * HY + bz * HZ) ^ 40
                local m = best.inv
                local qx = m[1] * px + m[2] * py + m[3] * pz + m[4]
                local qy = m[5] * px + m[6] * py + m[7] * pz + m[8]
                local qz = m[9] * px + m[10] * py + m[11] * pz + m[12]
                local k = shade and shade(qx, qy, qz, best, diff, spec, bx, by, bz, cuts[idx], params)
                if not k then
                    -- The red ramp, the default body: paper for the glint, blush
                    -- lit, red in the middle, slate in shadow -- with light bounced
                    -- back up off the page into the bottom of the shadow side,
                    -- without which the shadow side reads as a hole in the body.
                    if spec > 0.6 then k = "w"
                    elseif diff > 0.78 then k = "k"
                    elseif diff > 0.2 then k = "r"
                    elseif by < -0.55 and diff > 0.02 then k = "r"
                    else k = "s" end
                end
                ck[idx] = k
                nxs[idx] = bx
                nys[idx] = by
                nzs[idx] = bz
            end
        end
    end

    -- Creases, a step darker, so the planes read as planes: the bake's rule, a
    -- neighbour of the same material whose normal has turned far enough.
    local edge = model.edge
    local out = {}
    for j = j0, j1 do
        if (j - j0) % 16 == 15 then pause() end
        local base = (j - j0) * width - i0 + 1
        for i = i0, i1 do
            local idx = base + i
            local k = ck[idx]
            if k and k ~= "o" then
                local m = owner[idx].mat
                for step = 1, 2 do
                    local o = step == 1 and idx + 1 or idx + width
                    local inside = step == 1 and i < i1 or j < j1
                    if inside and ck[o] and owner[o].mat == m
                        and nxs[idx] * nxs[o] + nys[idx] * nys[o] + nzs[idx] * nzs[o] < CREASE then
                        if k == "k" or k == "r" then k = "s"
                        elseif (k == "w" or k == "g") and m ~= "body" then k = "s" end
                        break
                    end
                end
            end
            out[idx] = k
        end
    end

    -- Ink round the outside, and down the far side of any step in depth where
    -- one part stands in front of another (`edge`, in model units, if the model
    -- wants it).
    -- Each row's runs are packed three numbers a run -- from, to, colour -- in
    -- one flat list, to keep the kept pictures small.
    local rows = {}
    for j = j0, j1 do
        if (j - j0) % 16 == 15 then pause() end
        local base = (j - j0) * width - i0 + 1
        local runs, cur, from = {}, nil, nil
        for i = i0, i1 + 1 do
            local idx = base + i
            local k = i <= i1 and out[idx]
            local colour
            if k then
                local z = zd[idx]
                -- An empty neighbour is infinitely far: past the edge.
                local l = i > i0 and zd[idx - 1] or HUGE
                local r = i < i1 and zd[idx + 1] or HUGE
                local u = j > j0 and zd[idx - width] or HUGE
                local d = j < j1 and zd[idx + width] or HUGE
                if l == HUGE or r == HUGE or u == HUGE or d == HUGE then
                    k = "o"
                elseif edge then
                    -- Only against another part: one surface seen at a grazing
                    -- angle steps in depth from pixel to pixel too, and is not
                    -- an edge.
                    local me = owner[idx]
                    if (z - l > edge and owner[idx - 1] ~= me) or (z - r > edge and owner[idx + 1] ~= me)
                        or (z - u > edge and owner[idx - width] ~= me)
                        or (z - d > edge and owner[idx + width] ~= me) then
                        k = "o"
                    end
                end
                colour = key[k]
            end
            if colour ~= cur then
                if cur then
                    runs[#runs + 1] = from
                    runs[#runs + 1] = i
                    runs[#runs + 1] = cur
                end
                cur = colour
                from = i
            end
        end
        if #runs > 0 then rows[#rows + 1] = { j = j, runs = runs } end
    end

    local c = { rows = rows, frame = frame, yaw = yaw }
    -- Anything the model wants to know about the picture while its depths are
    -- still to hand (where the marble's eyes are, and whether they are seen).
    if model.after then
        model.after(c, q, function(x, y, z)
            local rx, ry, rz = Affine.apply(frame, x, y, z)
            local i = floor(rx / UNIT + 0.5)
            local j = floor(-(ry * CP - rz * SP) / UNIT + 0.5)
            local t = BACK - (ry * SP + rz * CP)
            if i < i0 or i > i1 or j < j0 or j > j1 then return i, j, nil, t end
            local idx = (j - j0) * width - i0 + 1 + i
            return i, j, owner[idx] and zd[idx] or nil, t
        end)
    end
    return c
end

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped under
-- it, a hit's rim, the flash.
function Solid:drawMask(x, y, pad)
    local ox, oy = floor(x), floor(y)
    pad = pad or 0
    for _, row in ipairs(self:raster().rows) do
        local runs = row.runs
        for k = 1, #runs, 3 do
            love.graphics.rectangle("fill", ox + runs[k] - pad, oy + row.j - pad,
                runs[k + 1] - runs[k] + pad * 2, 1 + pad * 2)
        end
    end
end

function Solid:draw(x, y)
    local ox, oy = floor(x), floor(y)
    local cur
    for _, row in ipairs(self:raster().rows) do
        local runs = row.runs
        for k = 1, #runs, 3 do
            local colour = runs[k + 2]
            if colour ~= cur then
                cur = colour
                love.graphics.setColor(cur)
            end
            love.graphics.rectangle("fill", ox + runs[k], oy + row.j, runs[k + 1] - runs[k], 1)
        end
    end
end

Solid.UNIT, Solid.PITCH = UNIT, PITCH

return Solid
