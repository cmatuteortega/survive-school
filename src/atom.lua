-- The atom boss's body: a nucleus painted a pixel at a time, and the orbits
-- round it.
--
-- The nucleus is the eye's method (src/eyeball.lua) pointed at a different
-- ball. Every pixel inside the outline is a point on a sphere, turned into the
-- sphere's own frame and asked which of a dozen nucleons it is nearest -- red
-- for a proton, white for a neutron, an ink seam where two of them meet -- and
-- then lit by the eye's own screen-fixed lamp. Turn the frame and the cluster
-- tumbles; the light stays put, which is what sells the tumble as a tumble.
--
-- The orbits are what makes it an atom rather than a ball, and they are the
-- one part of the drawing that is also the fight. Each is a circle in three
-- dimensions, tilted off the page by `tilt` towards the bearing `az`: seen face
-- on it is a circle, tipped over it is an ellipse, and edge on it is a line
-- through the middle. `az` turns all the time (`prec`), so a tipped ring swings
-- round the nucleus like a hoop spun on a table -- and when the brain (src/
-- atomboss.lua) swells one out across the box, that swing *is* the sweep.
--
-- Projected straight down onto the page, with z out of it towards you: half of
-- every ring is behind the nucleus and half in front, and the half behind is
-- drawn first so the nucleus covers it. Every pixel is a whole one in the eight
-- colours, laid as rectangles -- nothing is rotated, and the rings are plotted
-- point by point the way `pixelart` plots anything at an angle.
--
-- Nothing here is a hitbox. What hurts is worked out by the brain off
-- `Atom:point`, which is the same projection the drawing uses, so a ring hurts
-- exactly where it is drawn.

local Palette = require("src.palette")

local Atom = {}
Atom.__index = Atom

local RIM = 1 -- one pixel of ink: the rings are the heavy line on this body

-- How high the nucleus floats over its shadow, and the bob on top of that. It
-- hovers because nothing about an atom stands on anything, and because a ball
-- sat on the page with rings through it would put half of every ring under the
-- floor.
local HOVER, BOB = 5, 1.5

-- The eye's light, for the eye's reason: up, left and in front, fixed on the
-- screen.
local LX, LY, LZ = -0.48, -0.62, 0.62
do
    local n = math.sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX, LY, LZ + 1
do
    local n = math.sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end
local SHADE, DITHER, GLINT = 0.02, 0.18, 0.985

-- How wide the seam between two nucleons is, as a difference in how near the
-- point is to each; and how hard each one bulges. The light is worked out off
-- a normal tipped away from the middle of whichever nucleon the pixel is on,
-- so each is a little dome with its own lit side and its own shadow -- which
-- is what makes a cluster of them read as balls rather than as a map.
local SEAM, BULGE = 0.03, 2.4

local sqrt, floor, sin, cos, abs = math.sqrt, math.floor, math.sin, math.cos, math.abs
local TAU = math.pi * 2

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

-- The nucleons, spread over the sphere on a Fibonacci spiral so no two crowd
-- each other, and dealt protons and neutrons alternately. In the ball's frame,
-- so they tumble with it.
local function nucleons(n)
    local list = {}
    local golden = math.pi * (3 - sqrt(5))
    for i = 0, n - 1 do
        local y = 1 - (i + 0.5) / n * 2
        local r = sqrt(1 - y * y)
        local a = i * golden
        list[i + 1] = { cos(a) * r, y, sin(a) * r, proton = i % 2 == 0 }
    end
    return list
end

-- `radius` is the nucleus, `rings` how many orbits it has and `first` the
-- radius of the first: the rest go out `step` apart.
function Atom.new(radius, rings, first, step)
    local self = setmetatable({
        ax = { 1, 0, 0 }, ay = { 0, 1, 0 }, az = { 0, 0, 1 },
        t = love.math.random() * 10,
        nucleons = nil, rings = {},
        -- Written by the brain: how far it has stretched towards splitting, how
        -- hard it is shivering, and how hurt it is (which spins it faster).
        stretch = 0, shake = 0, jx = 0, hurt = 0,
        hidden = false,
    }, Atom)
    self:shape(radius, rings, first, step)
    return self
end

-- What size of atom this is: the whole one, or a half after it splits. The
-- orbits are dealt fresh, each at its own tilt and going its own way round, so
-- two halves never look like one atom drawn twice.
function Atom:shape(radius, rings, first, step)
    self.r = radius
    -- Where the shadow goes (Enemy:draw): under the nucleus, wherever its size
    -- puts the bottom of it.
    self.ground = radius + 1
    self.nucleons = nucleons(radius >= 11 and 20 or 12)
    self.rings = {}
    for k = 1, rings do
        local base = first + (k - 1) * step
        self.rings[k] = {
            base = base, r = base, grow = 1,
            tilt = 0.5 + love.math.random() * 0.8,
            az = k / rings * math.pi + love.math.random() * 0.4,
            tiltTo = nil, azTo = nil,
            prec = (k % 2 == 0 and -1 or 1) * (0.35 + love.math.random() * 0.2),
            phi = love.math.random() * TAU,
            spin = (k % 2 == 0 and -1 or 1) * (2.2 + k * 0.25),
            -- What the brain is doing with it: nil, "tell" or "hot" -- and
            -- how long the electron is gone for after it was thrown.
            state = nil, emptyT = 0,
        }
    end
end

--- the motion -----------------------------------------------------------------

local function rotate(v, kx, ky, kz, c, s)
    local x, y, z = v[1], v[2], v[3]
    local d = (kx * x + ky * y + kz * z) * (1 - c)
    v[1] = x * c + (ky * z - kz * y) * s + kx * d
    v[2] = y * c + (kz * x - kx * z) * s + ky * d
    v[3] = z * c + (kx * y - ky * x) * s + kz * d
end

-- Turned by `angle` about the unit axis k, then squared back up, for the eye's
-- reason: a frame turned a few thousand times by floats drifts out of true.
function Atom:turn(kx, ky, kz, angle)
    local c, s = cos(angle), sin(angle)
    rotate(self.ax, kx, ky, kz, c, s)
    rotate(self.ay, kx, ky, kz, c, s)
    rotate(self.az, kx, ky, kz, c, s)
    local a, b = self.az, self.ax
    local n = sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    a[1], a[2], a[3] = a[1] / n, a[2] / n, a[3] / n
    local d = b[1] * a[1] + b[2] * a[2] + b[3] * a[3]
    b[1], b[2], b[3] = b[1] - a[1] * d, b[2] - a[2] * d, b[3] - a[3] * d
    n = sqrt(b[1] * b[1] + b[2] * b[2] + b[3] * b[3])
    b[1], b[2], b[3] = b[1] / n, b[2] / n, b[3] / n
    local y = self.ay
    y[1] = a[2] * b[3] - a[3] * b[2]
    y[2] = a[3] * b[1] - a[1] * b[3]
    y[3] = a[1] * b[2] - a[2] * b[1]
end

-- One frame: the nucleus tumbles (quicker the more it is hurt), every orbit
-- swings round and its electron goes round it, and an orbit the brain has given
-- a new lie eases over to it.
function Atom:update(dt)
    if dt <= 0 then return end
    self.t = self.t + dt
    local w = 0.9 + self.hurt * 1.6
    self:turn(0.48, 0.8, 0.36, w * dt)

    for _, ring in ipairs(self.rings) do
        ring.az = (ring.az + ring.prec * dt) % TAU
        ring.phi = (ring.phi + ring.spin * dt) % TAU
        ring.emptyT = math.max(0, ring.emptyT - dt)
        local k = math.min(1, dt * 3)
        if ring.tiltTo then
            ring.tilt = ring.tilt + (ring.tiltTo - ring.tilt) * k
            if abs(ring.tiltTo - ring.tilt) < 0.005 then ring.tiltTo = nil end
        end
        ring.r = ring.base * ring.grow
    end

    self.jx = self.shake > 0
        and floor((love.math.random() - 0.5) * 2 * self.shake + 0.5) or 0
end

--- where things are -------------------------------------------------------------

-- The middle of the nucleus on the screen, off where the body is standing: up
-- off its shadow by the hover and the bob.
function Atom:centre(x, y)
    return floor(x) + self.jx + 0.5,
        floor(y) + 0.5 - HOVER - floor(BOB * sin(self.t * 2.4) + 0.5)
end

-- A point on an orbit, as an offset from the middle of the nucleus: x and y on
-- the screen, and z towards you. `r` overrides the orbit's own radius, which is
-- how the brain asks where a ring is *going* to be.
function Atom.point(ring, phi, r)
    r = r or ring.r
    local st, ct = sin(ring.tilt), cos(ring.tilt)
    local sa, ca = sin(ring.az), cos(ring.az)
    local cp, sp = cos(phi), sin(phi)
    return r * (-sa * cp - ct * ca * sp),
           r * (ca * cp - ct * sa * sp),
           r * st * sp
end

-- How many points to plot round an orbit of radius `r` so the dots join up.
function Atom.steps(r)
    return math.max(24, floor(TAU * r * 1.3))
end

-- The squash of a nucleus about to split: wider and shorter, the same area.
function Atom:radii()
    local s = self.stretch
    return self.r * (1 + s), self.r / (1 + s * 0.6)
end

function Atom:shadowScale()
    return (self.r / 13) * (1 + self.stretch)
end

--- drawing ----------------------------------------------------------------------

-- The span of row `j` inside an ellipse, or nil.
local function span(cx, cy, rx, ry, j)
    local v = (j + 0.5 - cy) / ry
    if v <= -1 or v >= 1 then return end
    local half = rx * sqrt(1 - v * v)
    local x0 = floor(cx - half + 0.5)
    local x1 = floor(cx + half + 0.5)
    if x1 <= x0 then return end
    return x0, x1
end

-- The nucleus's silhouette, `pad` out, in whatever colour is set: the blank
-- stamped under it, a hit's rim, the flash. The orbits are not part of it --
-- they are lines on the page as much as things over it, and a blank the width
-- of a ring would cut a white hoop through the ruling.
function Atom:drawMask(x, y, pad)
    local cx, cy = self:centre(x, y)
    local rx, ry = self:radii()
    rx, ry = rx + (pad or 0), ry + (pad or 0)
    for j = floor(cy - ry), floor(cy + ry) do
        local x0, x1 = span(cx, cy, rx, ry, j)
        if x0 then love.graphics.rectangle("fill", x0, j, x1 - x0, 1) end
    end
end

-- One orbit's half, behind the nucleus or in front of it, as a dotted ring with
-- its electron on it. Only orbits the brain has left alone: one it is telling
-- or has swollen out across the box is its to draw (AtomBoss:drawGround and
-- drawAir), over the floor and over the crowd.
local function drawOrbit(ring, cx, cy, front)
    if ring.state then return end
    local n = Atom.steps(ring.r)
    love.graphics.setColor(slate)
    for i = 0, n - 1, 3 do
        local px, py, pz = Atom.point(ring, i / n * TAU)
        if (pz >= 0) == front then
            love.graphics.rectangle("fill", floor(cx + px), floor(cy + py), 1, 1)
        end
    end
    if ring.emptyT <= 0 then
        local px, py, pz = Atom.point(ring, ring.phi)
        if (pz >= 0) == front then
            Atom.electron(cx + px, cy + py)
        end
    end
end

-- An electron: a red bead in an ink rim, the colour of everything that is
-- theirs. The same drawing on an orbit, on a swollen ring and thrown at you.
function Atom.electron(x, y)
    x, y = floor(x), floor(y)
    love.graphics.setColor(ink)
    love.graphics.rectangle("fill", x - 1, y - 2, 3, 5)
    love.graphics.rectangle("fill", x - 2, y - 1, 5, 3)
    love.graphics.setColor(red)
    love.graphics.rectangle("fill", x - 1, y - 1, 3, 3)
    love.graphics.setColor(blush)
    love.graphics.rectangle("fill", x - 1, y - 1, 1, 1)
end

-- The back halves of the orbits, the nucleus, and the front halves.
function Atom:draw(x, y)
    local cx, cy = self:centre(x, y)
    for _, ring in ipairs(self.rings) do drawOrbit(ring, cx, cy, false) end
    self:drawNucleus(cx, cy)
    for _, ring in ipairs(self.rings) do drawOrbit(ring, cx, cy, true) end
end

-- Every pixel of the cluster. Read top to bottom the questions are: is it the
-- rim; then, turned into the ball's frame, which nucleon is it nearest and how
-- near the next one is (the seam, and the curve into it); then how much light.
function Atom:drawNucleus(cx, cy)
    local rx, ry = self:radii()
    local irx, iry = rx - RIM, ry - RIM
    local ax, ay, az = self.ax, self.ay, self.az
    local list = self.nucleons

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

    for j = floor(cy - ry), floor(cy + ry) do
        local x0, x1 = span(cx, cy, rx, ry, j)
        if x0 then
            local sv = (j + 0.5 - cy) / iry
            for px = x0, x1 - 1 do
                local su = (px + 0.5 - cx) / irx
                local d = su * su + sv * sv
                local colour
                if d >= 1 then
                    colour = ink
                else
                    local sz = sqrt(1 - d)
                    local bx = ax[1] * su + ax[2] * sv + ax[3] * sz
                    local by = ay[1] * su + ay[2] * sv + ay[3] * sz
                    local bz = az[1] * su + az[2] * sv + az[3] * sz
                    local best, next, which = -2, -2, nil
                    for i = 1, #list do
                        local n = list[i]
                        local dot = n[1] * bx + n[2] * by + n[3] * bz
                        if dot > best then
                            best, next, which = dot, best, n
                        elseif dot > next then
                            next = dot
                        end
                    end
                    if best - next < SEAM then
                        colour = ink
                    else
                        -- The nucleon's middle, back out on the screen, and
                        -- the normal tipped away from it.
                        local n1, n2, n3 = which[1], which[2], which[3]
                        local mx = ax[1] * n1 + ay[1] * n2 + az[1] * n3
                        local my = ax[2] * n1 + ay[2] * n2 + az[2] * n3
                        local mz = ax[3] * n1 + ay[3] * n2 + az[3] * n3
                        local nx = su + BULGE * (su - mx * best)
                        local ny = sv + BULGE * (sv - my * best)
                        local nz = sz + BULGE * (sz - mz * best)
                        local len = sqrt(nx * nx + ny * ny + nz * nz)
                        local light = (LX * nx + LY * ny + LZ * nz) / len
                        local dark = light < SHADE
                            or (light < DITHER and (px + j) % 2 == 0)
                        if which.proton then
                            colour = dark and slate or (light > 0.55 and blush or red)
                        else
                            colour = dark and graphite or paper
                            if dark and light < SHADE - 0.3 then colour = slate end
                        end
                        if (HX * nx + HY * ny + HZ * nz) / len > GLINT then colour = paper end
                    end
                end
                put(px, j, colour)
            end
            flush(x1)
        end
    end
end

-- A swollen orbit drawn by the brain: the whole ring as a band `width` across
-- in `colour`, or dashed (`dash` pixels on, as many off, slid along by
-- `shift`), at radius `r` round (cx, cy).
function Atom.drawRing(ring, cx, cy, r, colour, width, dash, shift)
    local n = Atom.steps(r)
    love.graphics.setColor(colour)
    local half = floor((width or 1) / 2)
    local w = width or 1
    for i = 0, n - 1 do
        if not dash or floor((i + (shift or 0)) / dash) % 2 == 0 then
            local px, py = Atom.point(ring, i / n * TAU, r)
            love.graphics.rectangle("fill", floor(cx + px) - half, floor(cy + py) - half, w, w)
        end
    end
end

return Atom
