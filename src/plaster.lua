-- The ART boss's body: three plaster solids, painted a pixel at a time and lit
-- by a lamp that moves.
--
-- Every art class starts here. A white cube, a white sphere and a white cone on
-- a table under one lamp, and you draw what the light does to them: the side
-- that faces the lamp is the paper, the side that turns away is the darkest
-- your pencil goes, and the shadow each one throws across the table is a shape
-- of its own. This boss is that exercise, and it is drawn the eye's way and the
-- die's way at once (3dmethod.md) -- painted live rather than baked -- because
-- the one thing the exercise is about is the one thing a baked view cannot do:
-- **the light moves**. Sixteen pictures can turn a whistle to face you; none of
-- them can light a cube from wherever the lamp has got to. Painted fresh every
-- frame, the shading is just the lamp's direction dotted with a normal, and the
-- lamp going round the group is the whole body turning its lit side after it --
-- which is how the player reads where the light is before the shadows say so.
--
-- Three shapes, three ways of being met by a ray, all of them solved rather
-- than traced:
--
-- - **The cube** is the die's: six planes, the ray cut by each, inside if it
--   comes in before it goes out. Turned by its own three axes, so it can tumble
--   when it is thrown.
-- - **The sphere** is the eye's: a disc on the screen, the depth off Pythagoras.
-- - **The cone** is a quadratic: the set of points whose angle to the axis is
--   the cone's half-angle, cut by a ray along the view, with the base a plane.
--   Given by its apex and its axis, so it can stand on its base, lie on its
--   side or spin on its point like a top without a second piece of code.
--
-- Nearest hit wins, so the three overlap the way things on a table do.
--
-- **Pencil, not paint.** The other painted bosses are red, because a boss is
-- theirs. This one is plaster, and plaster is what you draw in pencil, so the
-- ramp is the page's own grey one: paper where the lamp falls, graphite in the
-- half-tone, slate in the core of the shadow, checkers between, and ink round
-- every edge. What makes it theirs is everything it does (src/stilllife.lua),
-- all of which is red; the body is the study.
--
-- **Edges from ids,** the die's way. Every pixel remembers which piece and which
-- face it is on, and a pixel whose right or lower neighbour is on another is
-- ink: the cube's creases, the cone's base, and the line where the sphere sits
-- in front of the cube all come out of the same test.
--
-- The room is the die's and the whistle's: tilted `PITCH` off looking straight
-- down, so the solids stand on a floor you see from above and in front. Room x
-- is the page's x, room y runs down the page along the floor, and z is up off
-- it -- so a lamp put on the page at some point is a lamp in the room at that
-- point, lifted to its own height.
--
-- Nothing here is a hitbox. Where the pieces stand round the boss, how a piece
-- is turned and whether one is off the table are drawing; the boss is still
-- `Enemy.x/y/radius` to everything else on the page, and what a piece does
-- while it is away is the brain's.

local Palette = require("src.palette")

local Plaster = {}
Plaster.__index = Plaster

local sqrt, floor, abs, cos, sin = math.sqrt, math.floor, math.abs, math.cos, math.sin

local function norm(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    if l < 1e-9 then return 0, 0, 1 end
    return x / l, y / l, z / l
end

-- The die's tilt, so the three painted rooms are one room.
local PITCH = 0.6
local CP, SP = cos(PITCH), sin(PITCH)

local function toScreen(x, y, z)
    return x, y * CP - z * SP, y * SP + z * CP
end
Plaster.toScreen = toScreen

-- How the light falls. `FILL` is light off the page itself, from where you are
-- looking: without it a lamp behind the group leaves every face you can see in
-- the same slate, and a study of a lamp behind three solids is three holes.
-- With it the core of the shadow is still slate, but the faces turned to you
-- are a step lighter than the ones turned away, so a cube lit from behind is
-- still a cube.
local FILL = 0.28
local LIT, HALF, MID, LOW = 0.62, 0.42, 0.2, 0.02

--- the pieces -----------------------------------------------------------------

-- A cube, `half` out to each face, sitting on the floor at (x, y). Its axes are
-- written in the room and start a little turned, so the first frame is a cube
-- and not a square.
function Plaster.cube(x, y, half)
    local a = 0.5
    return {
        kind = "cube", x = x, y = y, lift = 0, half = half,
        ax = { cos(a), sin(a), 0 }, ay = { -sin(a), cos(a), 0 }, az = { 0, 0, 1 },
    }
end

function Plaster.sphere(x, y, r)
    return { kind = "sphere", x = x, y = y, lift = 0, r = r }
end

-- A cone standing on its base, apex up. `apex` and `axis` (apex to base, unit)
-- are what it is: the brain lays it down or stands it on its point by moving
-- those two, and the painter never asks how it got there.
function Plaster.cone(x, y, r, h)
    return {
        kind = "cone", r = r, h = h,
        apex = { x, y, h }, axis = { 0, 0, -1 },
    }
end

-- Where a piece's middle is in the room, for its light and its box.
local function centre(p)
    if p.kind == "cube" then return p.x, p.y, p.half + p.lift end
    if p.kind == "sphere" then return p.x, p.y, p.r + p.lift end
    local a, d = p.apex, p.axis
    local m = p.h * 0.6
    return a[1] + d[1] * m, a[2] + d[2] * m, a[3] + d[3] * m
end
Plaster.centre = centre

-- Turned `angle` about the room axis (kx, ky, kz): the die's Rodrigues, on a
-- cube's three columns or a cone's one axis, squared up again after.
local function rotate(v, kx, ky, kz, c, s)
    local x, y, z = v[1], v[2], v[3]
    local d = (kx * x + ky * y + kz * z) * (1 - c)
    v[1] = x * c + (ky * z - kz * y) * s + kx * d
    v[2] = y * c + (kz * x - kx * z) * s + ky * d
    v[3] = z * c + (kx * y - ky * x) * s + kz * d
end

function Plaster.turn(p, kx, ky, kz, angle)
    kx, ky, kz = norm(kx, ky, kz)
    local c, s = cos(angle), sin(angle)
    if p.kind == "cube" then
        rotate(p.ax, kx, ky, kz, c, s)
        rotate(p.ay, kx, ky, kz, c, s)
        local ax, ay = p.ax, p.ay
        ax[1], ax[2], ax[3] = norm(ax[1], ax[2], ax[3])
        local d = ay[1] * ax[1] + ay[2] * ax[2] + ay[3] * ax[3]
        ay[1], ay[2], ay[3] = norm(ay[1] - d * ax[1], ay[2] - d * ax[2], ay[3] - d * ax[3])
        local az = p.az
        az[1] = ax[2] * ay[3] - ax[3] * ay[2]
        az[2] = ax[3] * ay[1] - ax[1] * ay[3]
        az[3] = ax[1] * ay[2] - ax[2] * ay[1]
    elseif p.kind == "cone" then
        local d = p.axis
        rotate(d, kx, ky, kz, c, s)
        d[1], d[2], d[3] = norm(d[1], d[2], d[3])
    end
end

-- A group of pieces painted together, standing on the page at the point it is
-- drawn at. `foot` is how far below that point the floor is drawn, so the bulk
-- of the group sits over the point its hitbox is round rather than above it.
function Plaster.new(pieces, foot)
    return setmetatable({
        pieces = pieces,
        foot = foot or 0,
        -- Where the lamp is, in the room, from this group's own floor point.
        lamp = { -40, -30, 30 },
        hidden = false,
        buf = {}, nx = {}, ny = {}, nz = {}, pid = {},
        dirty = true,
    }, Plaster)
end

-- Something moved: paint the silhouette again. The lamp moving does not need
-- this -- the silhouette is the same, only what colour it is changes.
function Plaster:touch() self.dirty = true end

--- painting -------------------------------------------------------------------

-- Each piece worked into the screen once per raster: centre, planes, axis.
local function prepare(p)
    local q = { kind = p.kind }
    if p.kind == "sphere" then
        q.cx, q.cy, q.cz = toScreen(p.x, p.y, p.r + p.lift)
        q.r = p.r
        q.lo, q.hi = { q.cx - q.r, q.cy - q.r }, { q.cx + q.r, q.cy + q.r }
    elseif p.kind == "cube" then
        local cx, cy, cz = toScreen(p.x, p.y, p.half + p.lift)
        q.cx, q.cy, q.cz = cx, cy, cz
        q.planes = {}
        for _, a in ipairs({ p.ax, p.ay, p.az }) do
            local sx, sy, sz = toScreen(a[1], a[2], a[3])
            local off = sx * cx + sy * cy + sz * cz
            q.planes[#q.planes + 1] = { sx, sy, sz, p.half + off }
            q.planes[#q.planes + 1] = { -sx, -sy, -sz, p.half - off }
        end
        local r = p.half * 1.75
        q.lo, q.hi = { cx - r, cy - r }, { cx + r, cy + r }
    else
        local a, d = p.apex, p.axis
        q.ax, q.ay, q.az = toScreen(a[1], a[2], a[3])
        q.dx, q.dy, q.dz = toScreen(d[1], d[2], d[3])
        q.h, q.r = p.h, p.r
        q.c2 = (p.h * p.h) / (p.h * p.h + p.r * p.r)
        local bx, by = q.ax + q.dx * p.h, q.ay + q.dy * p.h
        q.lo = { math.min(q.ax, bx - p.r), math.min(q.ay, by - p.r) }
        q.hi = { math.max(q.ax, bx + p.r), math.max(q.ay, by + p.r) }
    end
    return q
end

-- The nearest point of piece `q` along the ray through (u, v), as its depth,
-- which face it is on, and the screen normal there; nil for a miss.
local function hitSphere(q, u, v)
    local du, dv = u - q.cx, v - q.cy
    local d2 = du * du + dv * dv
    local r2 = q.r * q.r
    if d2 >= r2 then return nil end
    local dw = sqrt(r2 - d2)
    return q.cz + dw, 1, du / q.r, dv / q.r, dw / q.r
end

local function hitCube(q, u, v)
    local near, far, hit = 1e9, -1e9, 0
    for k, f in ipairs(q.planes) do
        local c = f[4] - f[1] * u - f[2] * v
        local a = f[3]
        if a > 1e-6 then
            local w = c / a
            if w < near then near, hit = w, k end
        elseif a < -1e-6 then
            local w = c / a
            if w > far then far = w end
        elseif c < 0 then
            return nil
        end
    end
    if near < far or hit == 0 then return nil end
    local f = q.planes[hit]
    return near, hit, f[1], f[2], f[3]
end

local function hitCone(q, u, v)
    local q1, q2 = u - q.ax, v - q.ay
    local dx, dy, dz = q.dx, q.dy, q.dz
    local k = q1 * dx + q2 * dy
    local m = q1 * q1 + q2 * q2
    local c2 = q.c2
    local best, face
    -- The side: (Q.D)^2 = c2 |Q|^2, with s the depth off the apex.
    local A = dz * dz - c2
    local B = 2 * k * dz
    local C = k * k - c2 * m
    local function side(s)
        local t = k + s * dz
        if t >= 0 and t <= q.h and (not best or s > best) then best, face = s, 1 end
    end
    if abs(A) < 1e-9 then
        if abs(B) > 1e-9 then side(-C / B) end
    else
        local disc = B * B - 4 * A * C
        if disc >= 0 then
            local sq = sqrt(disc)
            side((-B + sq) / (2 * A))
            side((-B - sq) / (2 * A))
        end
    end
    -- The base: the plane a whole height down the axis, inside the rim.
    if abs(dz) > 1e-6 then
        local s = (q.h - k) / dz
        if m + s * s - q.h * q.h <= q.r * q.r and (not best or s > best) then
            best, face = s, 2
        end
    end
    if not best then return nil end
    if face == 2 then return q.az + best, 2, dx, dy, dz end
    -- Outward off the side: c2 Q - (Q.D) D.
    local t = k + best * dz
    local nx, ny, nz = norm(c2 * q1 - t * dx, c2 * q2 - t * dy, c2 * best - t * dz)
    return q.az + best, 1, nx, ny, nz
end

local HIT = { sphere = hitSphere, cube = hitCube, cone = hitCone }

-- Every pixel in the box round the pieces asked which piece it lands on, and
-- its normal kept for the light. Once per change of shape, whatever asks -- the
-- blank, the outline and the body read the one answer.
function Plaster:raster()
    if not self.dirty then return end
    self.dirty = false
    local qs, idx = {}, {}
    local lox, loy, hix, hiy = 1e9, 1e9, -1e9, -1e9
    for k, p in ipairs(self.pieces) do
        if not p.hidden then
            local q = prepare(p)
            qs[#qs + 1], idx[#qs + 1] = q, k
            lox, loy = math.min(lox, q.lo[1]), math.min(loy, q.lo[2])
            hix, hiy = math.max(hix, q.hi[1]), math.max(hiy, q.hi[2])
        end
    end
    local buf, nx, ny, nz, pid = self.buf, self.nx, self.ny, self.nz, self.pid
    if #qs == 0 then
        self.w, self.h, self.x0, self.y0 = 0, 0, 0, 0
        return
    end
    local x0, y0 = floor(lox) - 2, floor(loy) - 2
    local w, h = floor(hix) + 3 - x0, floor(hiy) + 3 - y0
    for j = 0, h - 1 do
        local v = y0 + j + 0.5
        for i = 0, w - 1 do
            local u = x0 + i + 0.5
            local at = j * w + i + 1
            local bestW, id
            for n, q in ipairs(qs) do
                local dw, f, a, b, c = HIT[q.kind](q, u, v)
                if dw and (not bestW or dw > bestW) then
                    bestW, id = dw, idx[n] * 16 + f
                    nx[at], ny[at], nz[at], pid[at] = a, b, c, idx[n]
                end
            end
            buf[at] = id or 0
        end
    end
    self.x0, self.y0, self.w, self.h = x0, y0, w, h
end

local function solidAt(self, i, j)
    if i < 0 or j < 0 or i >= self.w or j >= self.h then return false end
    return self.buf[j * self.w + i + 1] ~= 0
end

-- Body: on a piece, or the ink ring one outside them; `pad` grows it.
local function bodyAt(self, i, j, pad)
    if solidAt(self, i, j) then return true end
    for d = 1, 1 + (pad or 0) do
        if solidAt(self, i - d, j) or solidAt(self, i + d, j)
            or solidAt(self, i, j - d) or solidAt(self, i, j + d) then
            return true
        end
        if d > 1 and (solidAt(self, i - d + 1, j - 1) or solidAt(self, i + d - 1, j + 1)
            or solidAt(self, i - 1, j + d - 1) or solidAt(self, i + 1, j - d + 1)) then
            return true
        end
    end
    return false
end

-- Where the box's corner lands on the canvas for a group drawn at (x, y).
function Plaster:origin(x, y)
    return floor(x) + self.x0, floor(y) + self.foot + self.y0
end

-- The silhouette in the current colour, `pad` pixels fat: the blank under it,
-- the red rim of a hit, the flash.
function Plaster:drawMask(x, y, pad)
    if self.hidden then return end
    self:raster()
    if self.w == 0 then return end
    local ox, oy = self:origin(x, y)
    pad = pad or 0
    for j = -1 - pad, self.h + pad do
        local run
        for i = -2 - pad, self.w + 1 + pad do
            local on = bodyAt(self, i, j, pad)
            if on and not run then run = i end
            if not on and run then
                love.graphics.rectangle("fill", ox + run, oy + j, i - run, 1)
                run = nil
            end
        end
    end
end

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite

-- A normal on the screen, lit by the lamp's direction (also on the screen),
-- down the pencil ramp. The checkers are keyed to the canvas pixel so they do
-- not crawl as the group moves.
local function shade(l, px, py)
    if l > LIT then return paper end
    if l > HALF then return (px + py) % 2 == 0 and paper or graphite end
    if l > MID then return graphite end
    if l > LOW then return (px + py) % 2 == 0 and graphite or slate end
    return slate
end

-- The light on each piece this frame: from its own middle to the lamp, so a
-- lamp brought in close lights the near side of the group and not the far.
function Plaster:lights()
    local L = {}
    local lx, ly, lz = self.lamp[1], self.lamp[2], self.lamp[3]
    for k, p in ipairs(self.pieces) do
        local cx, cy, cz = centre(p)
        L[k] = { toScreen(norm(lx - cx, ly - cy, lz - cz)) }
    end
    return L
end

function Plaster:draw(x, y)
    if self.hidden then return end
    self:raster()
    if self.w == 0 then return end
    local buf, nx, ny, nz, pid = self.buf, self.nx, self.ny, self.nz, self.pid
    local w, h = self.w, self.h
    local ox, oy = self:origin(x, y)
    local L = self:lights()

    local cur, runX, runY
    local function flush(px)
        if cur then love.graphics.rectangle("fill", runX, runY, px - runX, 1) end
        cur = nil
    end
    local function put(px, py, colour)
        if colour ~= cur then
            flush(px)
            love.graphics.setColor(colour)
            cur, runX, runY = colour, px, py
        end
    end

    for j = -1, h do
        for i = -2, w + 1 do
            local px, py = ox + i, oy + j
            local k = (i >= 0 and j >= 0 and i < w and j < h) and buf[j * w + i + 1] or 0
            local colour
            if k == 0 then
                if bodyAt(self, i, j, 0) then colour = ink end
            elseif not (solidAt(self, i - 1, j) and solidAt(self, i + 1, j)
                and solidAt(self, i, j - 1) and solidAt(self, i, j + 1)) then
                colour = ink
            else
                local right = buf[j * w + i + 2]
                local below = buf[(j + 1) * w + i + 1]
                if right ~= k or below ~= k then
                    colour = ink
                else
                    local at = j * w + i + 1
                    local l = L[pid[at]]
                    local a, b, c = nx[at], ny[at], nz[at]
                    local lit = math.max(0, a * l[1] + b * l[2] + c * l[3])
                    colour = shade(lit * (1 - FILL) + c * FILL, px, py)
                end
            end
            if colour then put(px, py, colour) else flush(px) end
        end
        flush(ox + w + 2)
    end
end

-- No mark under it from the enemy's own shadow: the shadows a still life throws
-- are cast by the lamp (src/stilllife.lua), which knows where it is. Except the
-- glue's smear, which is not a shadow but the one way a stuck thing says so.
function Plaster:shadowScale(_, stuck)
    return stuck and 1 or 0
end

return Plaster
