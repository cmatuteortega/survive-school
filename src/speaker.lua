-- The speaker's body: a cylindrical bluetooth speaker, painted a pixel at a time.
--
-- The piggy bank's method (src/piggy.lua) on one solid with flat ends: every
-- pixel is a ray fired straight into the page and asked where it first meets the
-- can -- its curved side (a quadratic along the ray, as the pig's ellipsoids are,
-- with the axis term left out) or one of its two caps (a plane, so a division) --
-- and lit by the eye's own screen-fixed lamp. Seen from a little above (`ELEV`)
-- like the pig, because a can looked at straight down is a circle, and every
-- one of the things that make it *that* speaker is on its side or its top.
--
-- What makes it read as a speaker and not as a tin:
--
--  - **The knit.** The side is fabric, and fabric is a pattern: ribs every few
--    pixels of height, run round the can, so on the screen they are ellipses --
--    the single strongest cue in the picture that this is a round thing, and the
--    one that shows it rolling when it tips over and rolls (src/speakerboss.lua).
--  - **The buttons.** A big + over a big - on its front, the way every speaker
--    of this shape is sold. It turns to face you, so the + is what you see; it
--    lights when the volume goes up.
--  - **The ring.** A ring of lights round the edge of its top cap, which is
--    how it says what it is doing: a meter of how loud it is, red while a drop
--    builds, blue while it pairs, dark when glue has muted it.
--  - **The radiator.** The rest of the top is a passive radiator, which pumps
--    with the bass: its normal is pushed out round the middle by `pump`, so the
--    light on it swells and drains on every beat without a pixel of it moving.
--  - **The logo.** A bluetooth rune on its back, which it turns round to show
--    you when it pairs with the crowd.
--
-- And it **squashes and stretches**: `squash` widens and shortens it (a kick),
-- below zero narrows and lengthens it (the build before a drop), with its foot
-- kept on the page so it is the can and not the page that gives.
--
-- Its orientation is a frame rather than a heading, because it does not only
-- turn: it tips over onto its side and rolls, and stands back up. `F` (its
-- front, where the buttons are), `S` and `U` (up its axis) are three directions
-- on the page -- x across, y down the page, h up off it -- turned by small
-- rotations every frame and put straight again, so a roll is the can turning
-- about its own axis and a bounce off the box turns the whole of it at once.
--
-- Drawn the eye's way otherwise: runs of one colour along a row, eight colours,
-- no alpha, an ink rim round the outside and along any edge where one part of
-- it stands in front of another. Worked out once a frame and kept (`raster`).

local Palette = require("src.palette")

local Speaker = {}
Speaker.__index = Speaker

local sqrt, floor, sin, cos, abs, atan2 = math.sqrt, math.floor, math.sin, math.cos, math.abs, math.atan2
local TAU = math.pi * 2

-- How far above the page it is seen from, the pig's half radian: enough of the
-- top to show the ring and the radiator, and enough of the side for the buttons.
local ELEV = 0.5
local CE, SE = cos(ELEV), sin(ELEV)

-- Its radius and half its height: 22 across and 30 tall, about the pig's bulk
-- stood on end.
local RAD, HALF = 11, 15

-- Where e.y is against the drawing: the middle of the can is drawn this far
-- above it, so the hit circle round e.y covers the body rather than its feet.
local MID = 5

-- The eye's lamp: up, left and in front, fixed on the screen.
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
local GLINT = 0.985

-- The rubber trim round both ends, and the ring of lights inside the top's, as
-- distances in from the edge.
local TRIM, RING_IN, RING_OUT = 2.6, 4.2, 2.2
-- How many lights the ring is cut into.
local LIGHTS = 12
-- A rib of the knit every this many units of height.
local RIB = 3.4

-- Past this much depth between two neighbouring pixels it is an edge.
local EDGE = 2.5

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush, blue, sky = Palette.red, Palette.blush, Palette.blue, Palette.sky

-- The bluetooth rune, on the back of the can: 5 wide, 9 tall, in its own
-- (round the can, up the can) units.
local RUNE = {
    "..x..",
    "..xx.",
    "x.x.x",
    ".xxx.",
    "..x..",
    ".xxx.",
    "x.x.x",
    "..xx.",
    "..x..",
}

--- page vectors -----------------------------------------------------------------

local function norm(x, y, h)
    local n = sqrt(x * x + y * y + h * h)
    if n == 0 then return 0, 0, 1 end
    return x / n, y / n, h / n
end

local function cross(ax, ay, ah, bx, by, bh)
    return ay * bh - ah * by, ah * bx - ax * bh, ax * by - ay * bx
end

-- (vx, vy, vh) turned by `a` about the unit axis (kx, ky, kh): Rodrigues.
local function turn(vx, vy, vh, kx, ky, kh, a)
    local c, s = cos(a), sin(a)
    local cx, cy, ch = cross(kx, ky, kh, vx, vy, vh)
    local d = (kx * vx + ky * vy + kh * vh) * (1 - c)
    return vx * c + cx * s + kx * d, vy * c + cy * s + ky * d, vh * c + ch * s + kh * d
end

function Speaker.new()
    return setmetatable({
        -- Its frame on the page: front, side and axis.
        F = { 0, 1, 0 }, S = { -1, 0, 0 }, U = { 0, 0, 1 },
        -- Written by the brain every frame: how squashed it is, how far the
        -- radiator is pushed out, how high off the page it is bouncing, how
        -- hard it is shaking, what the ring is showing, whether the + is lit and
        -- whether the rune is.
        squash = 0, pump = 0, hop = 0, shake = 0, jx = 0,
        lights = { colour = "sky", lit = 1, spin = 0 },
        plus = false, rune = false,
        ground = floor(HALF * CE - MID + 0.5),
        hidden = false,
        dirty = true, cache = nil,
    }, Speaker)
end

--- the motion -------------------------------------------------------------------

-- Every vector of the frame turned by `a` about a page direction.
function Speaker:rotate(kx, ky, kh, a)
    if a == 0 then return end
    kx, ky, kh = norm(kx, ky, kh)
    for _, v in ipairs({ self.F, self.S, self.U }) do
        v[1], v[2], v[3] = turn(v[1], v[2], v[3], kx, ky, kh, a)
    end
end

-- Put square again: small turns every frame drift, and a frame that is not
-- square is a can that is not round.
function Speaker:square()
    local U, F = self.U, self.F
    U[1], U[2], U[3] = norm(U[1], U[2], U[3])
    local d = F[1] * U[1] + F[2] * U[2] + F[3] * U[3]
    F[1], F[2], F[3] = norm(F[1] - U[1] * d, F[2] - U[2] * d, F[3] - U[3] * d)
    local S = self.S
    S[1], S[2], S[3] = cross(U[1], U[2], U[3], F[1], F[2], F[3])
end

-- How far it is over: 0 stood up, 1 on its side.
function Speaker:lean()
    return 1 - abs(self.U[3])
end

-- Turned about the page's own up towards a heading, at `rate` radians a second
-- (math.huge for at once). Only its front's lie on the page is read, so this is
-- the right turn whether it is stood up or lying down.
function Speaker:face(dx, dy, rate, dt)
    if dx == 0 and dy == 0 then return end
    local F = self.F
    if abs(F[1]) + abs(F[2]) < 0.05 then return end
    local d = (atan2(dy, dx) - atan2(F[2], F[1]) + math.pi) % TAU - math.pi
    local most = rate * dt
    if rate ~= math.huge and abs(d) > most then d = d > 0 and most or -most end
    self:rotate(0, 0, 1, d)
end

-- Spun about the page's up by `a`, whatever it is facing: the turn it makes to
-- show its back, and a bounce turning the whole can.
function Speaker:spin(a)
    self:rotate(0, 0, 1, a)
end

-- Tipped over sideways so that it can roll along (dx, dy) -- turned about that
-- direction, so its axis goes down across the way it will roll -- by at most
-- `a`, stopping once it is on its side.
function Speaker:tip(dx, dy, a)
    local U = self.U
    local left = math.acos(math.max(-1, math.min(1, abs(U[3]))))
    a = math.min(a, math.pi / 2 - left)
    -- Turned so its top goes down the page rather than up it: what lies
    -- towards you is the end with the lights on it, not the rubber foot.
    if dx > 0 then a = -a end
    if a ~= 0 then self:rotate(dx, dy, 0, a) end
end

-- Stood back up, by at most `a`: turned about whatever axis takes its own
-- straightest up, and whichever end is nearer the sky ends up on top -- which is
-- the end with the lights on it, since it only ever goes over sideways.
function Speaker:right(a)
    local U = self.U
    local kx, ky, kh = cross(U[1], U[2], U[3], 0, 0, 1)
    local n = sqrt(kx * kx + ky * ky + kh * kh)
    if n < 1e-4 then return end
    local left = math.acos(math.max(-1, math.min(1, U[3])))
    self:rotate(kx, ky, kh, math.min(a, left))
end

-- Rolled along the page by `dist` going (dx, dy): turned about the axis a wheel
-- going that way turns about, which while it lies across the way it goes is its
-- own -- so the knit and the buttons go round.
function Speaker:roll(dx, dy, dist)
    local kx, ky, kh = cross(0, 0, 1, dx, dy, 0)
    self:rotate(kx, ky, kh, dist / RAD)
end

function Speaker:update(dt)
    self:square()
    self.jx = self.shake > 0
        and floor((love.math.random() - 0.5) * 2 * self.shake + 0.5) or 0
    self.dirty = true
end

--- where things are -------------------------------------------------------------

-- Its two extents, squashed: radius and half height.
function Speaker:size()
    local q = self.squash
    return RAD * (1 + 0.16 * q), HALF * (1 - 0.2 * q)
end

-- How high the middle of the can is off the page: its half height stood up, its
-- radius lying down, and in between whatever it is leaning on.
function Speaker:height()
    local r, h = self:size()
    local up = abs(self.U[3])
    return h * up + r * sqrt(math.max(0, 1 - up * up))
end

-- The middle of the can on the screen, off where e.x, e.y is. Its foot stays
-- where it was as it squashes: the middle comes down, not the page up.
function Speaker:centre(x, y)
    local foot = HALF * CE - MID
    return floor(x) + self.jx + 0.5, floor(y) + 0.5 + foot - self:height() * CE - self.hop
end

-- Where its foot is on the screen against e.y, for the shadow (Enemy:draw).
function Speaker:footY()
    return floor(HALF * CE - MID + 0.5)
end

-- Where the middle of its top cap is on the screen: where the drop goes off,
-- and where the notes come out.
function Speaker:top(x, y)
    local cx, cy = self:centre(x, y)
    local _, h = self:size()
    local U = self.U
    return cx + U[1] * h, cy + (U[2] * SE - U[3] * CE) * h
end

function Speaker:shadowScale(hop)
    return 1 - (self.hop or 0) * 0.04 + self:lean() * 0.25
end

--- drawing ----------------------------------------------------------------------

-- A page direction on the screen: x across, y down, z towards you.
local function screen(v)
    return v[1], v[2] * SE - v[3] * CE, v[2] * CE + v[3] * SE
end

-- Which of the ring's lights a direction round the top is, 1 to LIGHTS.
local function lightAt(angle, spin)
    return floor(((angle + spin) % TAU) / TAU * LIGHTS) % LIGHTS + 1
end

-- What the ring shows at light `k`.
local function ringColour(lights, k, checker)
    if lights.colour == "off" then return checker and slate or ink end
    if k > lights.lit then return checker and slate or ink end
    local c = Palette[lights.colour] or sky
    if lights.colour == "cycle" then
        local seq = { red, blush, paper, sky, blue }
        c = seq[(k + floor(lights.spin * 2)) % #seq + 1]
    end
    return c
end

-- The picture, as rows of runs: worked out at most once a frame, relative to
-- the middle of the can.
function Speaker:raster()
    if not self.dirty and self.cache then return self.cache end
    local Fx, Fy, Fz = screen(self.F)
    local Sx, Sy, Sz = screen(self.S)
    local Ux, Uy, Uz = screen(self.U)
    local rad, half = self:size()
    local R = 28
    local lights, pump = self.lights, self.pump
    local r2 = rad * rad

    local zbuf, cbuf = {}, {}
    local i0, i1, j0, j1 = -R, R, -R, R
    for j = j0, j1 do
        local zrow, crow = {}, {}
        zbuf[j], cbuf[j] = zrow, crow
        for i = i0, i1 do
            -- The ray's body coordinates are a + z * b along each axis.
            local af, bf = i * Fx + j * Fy, Fz
            local as, bs = i * Sx + j * Sy, Sz
            local au, bu = i * Ux + j * Uy, Uz
            local bestZ, part

            -- The curved side.
            local qa = bf * bf + bs * bs
            if qa > 1e-6 then
                local qb = af * bf + as * bs
                local qc = af * af + as * as - r2
                local disc = qb * qb - qa * qc
                if disc >= 0 then
                    local z = (-qb + sqrt(disc)) / qa
                    local u = au + z * bu
                    if u >= -half and u <= half then bestZ, part = z, "side" end
                end
            end
            -- The two caps.
            if abs(bu) > 1e-6 then
                for _, end_ in ipairs({ half, -half }) do
                    local z = (end_ - au) / bu
                    if not bestZ or z > bestZ then
                        local f, s = af + z * bf, as + z * bs
                        if f * f + s * s <= r2 then
                            bestZ, part = z, end_ > 0 and "top" or "bottom"
                        end
                    end
                end
            end

            if bestZ then
                zrow[i] = bestZ
                local f, s, u = af + bestZ * bf, as + bestZ * bs, au + bestZ * bu
                local checker = (i + j) % 2 == 0
                local nf, ns, nu
                if part == "side" then
                    nf, ns, nu = f / rad, s / rad, 0
                else
                    local sign = part == "top" and 1 or -1
                    -- The radiator: pushed out round the middle, so its light
                    -- swells on the beat. Only inside the ring.
                    local rr = sqrt(f * f + s * s)
                    local inner = rad - RING_IN
                    if part == "top" and rr < inner and pump ~= 0 then
                        local k = pump * 1.4 / inner
                        nf, ns, nu = f * k, s * k, 1
                    else
                        nf, ns, nu = 0, 0, sign
                    end
                end
                local nx = nf * Fx + ns * Sx + nu * Ux
                local ny = nf * Fy + ns * Sy + nu * Uy
                local nz = nf * Fz + ns * Sz + nu * Uz
                local len = sqrt(nx * nx + ny * ny + nz * nz)
                nx, ny, nz = nx / len, ny / len, nz / len
                local light = LX * nx + LY * ny + LZ * nz
                local glint = HX * nx + HY * ny + HZ * nz > GLINT

                local colour
                if part == "side" then
                    local around = atan2(s, f)
                    if abs(u) > half - TRIM then
                        -- The rubber trim round each end.
                        colour = light > 0.25 and slate or (checker and slate or ink)
                    else
                        -- The knit, lit: sky where the lamp is on it, blue,
                        -- then slate in its own shadow -- dithered only where
                        -- one shade gives onto the next, so the buttons on it
                        -- still read.
                        if light > 0.62 then
                            colour = checker and paper or sky
                        elseif light > 0.3 then
                            colour = sky
                        elseif light > 0.05 then
                            colour = checker and blue or sky
                        elseif light > -0.4 then
                            colour = blue
                        else
                            colour = checker and slate or blue
                        end
                        -- The ribs, round it: ellipses on the screen.
                        if (u + half) % RIB < 0.9 then
                            colour = (colour == paper or colour == sky) and blue or slate
                        end
                        if glint then colour = paper end
                        -- The buttons on its front, as lengths round the can and
                        -- up it: a + over a -, each in an ink keyline so it reads
                        -- on the knit.
                        local x = around * rad
                        local ax = abs(x)
                        if ax < 7 then
                            local py, my = abs(u - half * 0.33), abs(u + half * 0.33)
                            local function plus(g)
                                return (ax < 4.2 + g and py < 1.3 + g) or (ax < 1.3 + g and py < 4.2 + g)
                            end
                            local function minus(g) return ax < 4.2 + g and my < 1.3 + g end
                            if plus(0) then
                                colour = self.plus and red or (light > -0.2 and paper or graphite)
                            elseif minus(0) then
                                colour = light > -0.2 and paper or graphite
                            elseif plus(0.9) or minus(0.9) then
                                colour = ink
                            end
                        end
                        -- And the rune on its back, on a dark badge.
                        local bx = ((around + TAU) % TAU - math.pi) * rad
                        local col = floor(bx + 3)
                        local row = floor(half * 0.25 - u + 5)
                        if col >= 0 and col <= 6 and row >= 0 and row <= #RUNE + 1 then
                            colour = ink
                            if col >= 1 and col <= 5 and row >= 1 and row <= #RUNE
                                and RUNE[row]:sub(col, col) == "x" then
                                colour = self.rune and (checker and blue or paper) or slate
                            end
                        end
                    end
                elseif part == "top" then
                    local rr = sqrt(f * f + s * s)
                    if rr > rad - RING_OUT then
                        colour = light > 0.3 and slate or ink
                    elseif rr > rad - RING_IN then
                        local k = lightAt(atan2(s, f), lights.spin)
                        colour = ringColour(lights, k, checker)
                    elseif rr < 1.6 then
                        colour = slate
                    else
                        -- The radiator, rubber-dark and lit off its pushed-out
                        -- normal, with a groove a third of the way in.
                        if light > 0.75 then
                            colour = checker and graphite or slate
                        elseif light > 0.45 then
                            colour = checker and slate or graphite
                        else
                            colour = checker and ink or slate
                        end
                        if abs(rr - (rad - RING_IN) * 0.55) < 0.5 then colour = ink end
                        if glint then colour = paper end
                    end
                else
                    colour = checker and ink or slate
                end
                crow[i] = colour
            end
        end
    end

    -- The rim, and the edges where one part stands in front of another.
    local rows = {}
    for j = j0, j1 do
        local zrow, crow = zbuf[j], cbuf[j]
        local up, down = zbuf[j - 1] or {}, zbuf[j + 1] or {}
        local runs, cur, from = {}, nil, nil
        for i = i0, i1 + 1 do
            local z = zrow[i]
            local colour
            if z then
                local l, r, a, b = zrow[i - 1], zrow[i + 1], up[i], down[i]
                if not (l and r and a and b) then
                    colour = ink
                elseif l - z > EDGE or r - z > EDGE or a - z > EDGE or b - z > EDGE then
                    colour = ink
                else
                    colour = crow[i]
                end
            end
            if colour ~= cur then
                if cur then runs[#runs + 1] = { from, i, cur } end
                cur, from = colour, i
            end
        end
        if #runs > 0 then rows[#rows + 1] = { j = j, runs = runs } end
    end

    self.cache, self.dirty = rows, false
    return rows
end

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped
-- under it, a hit's rim, the flash.
function Speaker:drawMask(x, y, pad)
    local cx, cy = self:centre(x, y)
    local ox, oy = floor(cx), floor(cy)
    pad = pad or 0
    for _, row in ipairs(self:raster()) do
        for _, run in ipairs(row.runs) do
            love.graphics.rectangle("fill", ox + run[1] - pad, oy + row.j - pad,
                run[2] - run[1] + pad * 2, 1 + pad * 2)
        end
    end
end

function Speaker:draw(x, y)
    local cx, cy = self:centre(x, y)
    local ox, oy = floor(cx), floor(cy)
    local cur
    for _, row in ipairs(self:raster()) do
        for _, run in ipairs(row.runs) do
            if run[3] ~= cur then
                cur = run[3]
                love.graphics.setColor(cur)
            end
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

return Speaker
