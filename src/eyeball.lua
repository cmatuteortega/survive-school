-- The eye boss's body: a ball rather than a picture of one.
--
-- Every other monster is a sprite, and so was this one -- a flat white disc with
-- a pupil slid across it. Slid is the problem: a disc moving across a disc reads
-- as a sticker on a plate, and the one enemy whose drawing says which way it is
-- facing was saying it in two dimensions. So the eye is painted a pixel at a time
-- off a real sphere instead. Every pixel inside the outline is a point on the
-- ball, turned into the ball's own frame, and asked whether it is iris, pupil,
-- vein or white -- which is what makes an iris looking off to the side go thin
-- and oval the way it would on a real eye, and what lets the whole ball *roll*:
-- turn the frame and every vein and fibre comes round with it.
--
-- This is still the rendering rules, not an exception to them. What comes out
-- is whole pixels on the canvas grid in the eight colours, written as horizontal
-- runs (`love.graphics.rectangle`), the same thing `pixelart.circleFill` does --
-- nothing is rotated, and the light is screen-fixed, so the shading and the
-- catchlight stay put while the ball turns underneath them, which is most of
-- what sells the turn as a turn. Fades are dither, as everywhere else.
--
-- It also carries how the boss moves, because how it moves and how it looks are
-- one thing here. The boss walks at a fixed average speed (Enemy.types) and that
-- number is a design decision this file must not move, so the gait only
-- *redistributes* it: it glides, or it hops -- stopped on the ground, quick in
-- the air, the two averaging out to the row's speed -- or it rolls a stretch a
-- little quicker and then sits dizzy for a moment while the eye finds you again.
-- Every peak stays well under the player's 58, so walking away still works; what
-- changed is that the walking-away has a rhythm to read.
--
-- Nothing here is a hitbox. Height, squash and the roll are all drawing; the
-- thing the crowd, the bullets and the box measure is still `Enemy.x/y/radius`,
-- for the same reason the hit recoil is folded in at the draw (Enemy:footing).

local Palette = require("src.palette")
local Camera = require("src.camera")
local util = require("src.util")

local Eyeball = {}
Eyeball.__index = Eyeball

local RADIUS = 21   -- the outline at rest: 43 across, the sprite it replaced
local RIM = 3       -- the ink border. A boss is the heaviest line on the page
local IRIS = 0.56   -- angular radius of the iris on the ball, in radians: ~19 across
local LIMBUS = 0.10 -- the dark ring round it, the same unit
local COLLAR = 0.36 -- where the fibres stop, nearer the pupil
local PUPIL = 0.25  -- the pupil's own angle at rest: ~9 across
local LOOK = 0.78   -- how far the ball turns to face you, radians

-- The light: up, to the left and in front, fixed on the screen. Fixed is the
-- point -- the ball turns and the light does not, so the shadow crescent and the
-- catchlight are what tell you the ball is round.
local LX, LY, LZ = -0.48, -0.62, 0.62
do
    local n = math.sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX, LY, LZ + 1 -- half way between the light and the eye
do
    local n = math.sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end
local SHADE = 0.02   -- below this much light it is in shadow,
local DITHER = 0.16  -- and below this it is half in it (checkered)
local GLINT = 0.988  -- and above this much highlight it is the catchlight

-- The springs. The ball's turn is a damped spring rather than a chase so that
-- it overshoots: coming out of a roll, the eye swings past you and back, which
-- is what makes it look like it is *finding* you. The squash is a softer and
-- bouncier spring for the jelly -- underdamped enough to wobble twice after a
-- landing and no more.
local TURN_K, TURN_C = 140, 15
local SQUASH_K, SQUASH_C = 320, 9
local SQUASH_MIN, SQUASH_MAX = -0.24, 0.32

-- The gait. Each mode's speed share is chosen to average out to 1 over the
-- mode: a hop stands still for CROUCH + SETTLE and makes it up in the air, and
-- a roll runs a bit over and pays it back sitting dizzy.
local WALK = { 1.4, 2.6 }       -- how long it glides between tricks
local HOPS = { 3, 5 }
local CROUCH, AIR, SETTLE = 0.12, 0.36, 0.08
local HOP_HIGH, LAST_HIGH = 8, 15 -- the last hop of a run is the big one
local ROLL = { 1.4, 1.9 }
local ROLL_SPEED = 1.35
local DIZZY = 0.55
local BLINK = 0.18

local sqrt, floor, atan2, sin, cos, abs = math.sqrt, math.floor, math.atan2,
    math.sin, math.cos, math.abs

local function between(r)
    return r[1] + love.math.random() * (r[2] - r[1])
end

function Eyeball.new()
    local self = setmetatable({
        -- The ball's own axes, written in screen space (x right, y down, z out
        -- of the page): the columns of the turn. `az` is where it is looking.
        ax = { 1, 0, 0 }, ay = { 0, 1, 0 }, az = { 0, 0, 1 },
        wx = 0, wy = 0, wz = 0, -- how fast it is turning, about each screen axis
        squash = 0, squashV = 0, squashTo = 0,
        lift = 0,
        mode = "walk", modeT = between(WALK),
        phase = nil, phaseT = 0, hops = 0,
        blinkT = 1.5 + love.math.random() * 3, blinkP = 0,
        squint = 0, pinch = 0, dilate = 0,
        glanceX = 0, glanceY = 0, glanceT = 1,
        thud = nil, skidT = 0, breath = 0,
    }, Eyeball)

    -- Its own handful of veins, each a line of longitude round the iris with a
    -- wobble in it, running from the back of the ball to somewhere short of the
    -- iris. In the ball's frame, so they roll with it.
    self.veins = {}
    for i = 1, 7 do
        self.veins[i] = {
            phi = (i + love.math.random() * 0.6) * math.pi * 2 / 7,
            reach = 0.3 + love.math.random() * 0.45,
            wob = 0.12 + love.math.random() * 0.2,
            freq = 6 + love.math.random() * 6,
            fork = love.math.random() < 0.5 and 0.35 + love.math.random() * 0.15 or nil,
        }
    end
    return self
end

-- The squash shape: wider and shorter for a positive squash, the other way for
-- a stretch, keeping roughly the same area so it reads as the same ball.
function Eyeball:radii()
    local s = self.squash
    return RADIUS * (1 + s), RADIUS / (1 + s)
end

-- How much wider the shadow under it is than at rest: narrower the higher it
-- is off the page, wider as it flattens onto it.
function Eyeball:shadowScale()
    return (1 + self.squash) * math.max(0.45, 1 - self.lift / 30)
end

local function rotate(v, kx, ky, kz, c, s)
    -- Rodrigues, about the unit axis k by the angle whose cos/sin are c/s.
    local x, y, z = v[1], v[2], v[3]
    local d = (kx * x + ky * y + kz * z) * (1 - c)
    v[1] = x * c + (ky * z - kz * y) * s + kx * d
    v[2] = y * c + (kz * x - kx * z) * s + ky * d
    v[3] = z * c + (kx * y - ky * x) * s + kz * d
end

-- Turns the frame by the angular velocity for `dt`, then squares it back up --
-- a frame turned a few thousand times by floats drifts out of true, and an iris
-- painted off a skewed frame would slowly go egg-shaped.
function Eyeball:spin(dt)
    local w = sqrt(self.wx * self.wx + self.wy * self.wy + self.wz * self.wz)
    if w * dt < 1e-6 then return end
    local kx, ky, kz = self.wx / w, self.wy / w, self.wz / w
    local c, s = cos(w * dt), sin(w * dt)
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

-- Swings the gaze towards (tx, ty, tz) on the turn spring.
function Eyeball:track(dt, tx, ty, tz)
    local f = self.az
    local cx = f[2] * tz - f[3] * ty
    local cy = f[3] * tx - f[1] * tz
    local cz = f[1] * ty - f[2] * tx
    local s = sqrt(cx * cx + cy * cy + cz * cz)
    local c = f[1] * tx + f[2] * ty + f[3] * tz
    local ang = atan2(s, c)
    if s > 1e-6 then
        cx, cy, cz = cx / s * ang, cy / s * ang, cz / s * ang
    elseif c < 0 then
        -- Looking dead away: any axis at right angles will do.
        cx, cy, cz = self.ax[1] * ang, self.ax[2] * ang, self.ax[3] * ang
    end
    self.wx = self.wx + (cx * TURN_K - self.wx * TURN_C) * dt
    self.wy = self.wy + (cy * TURN_K - self.wy * TURN_C) * dt
    self.wz = self.wz + (cz * TURN_K - self.wz * TURN_C) * dt
end

-- One frame. `x, y` is where the boss is standing and `stuck` is whether it is
-- glued; returns the share of its speed it walks at this frame.
function Eyeball:update(dt, x, y, player, stuck)
    if dt <= 0 then return 1 end

    -- What it actually moved last frame, crowd and box and walls included, which
    -- is what a roll has to turn by -- a ball that spun at its intended speed
    -- while jammed against the arena would be skating.
    local mx, my = 0, 0
    if self.lastX then mx, my = x - self.lastX, y - self.lastY end
    self.lastX, self.lastY = x, y

    local share = 1
    local rolling = false

    if stuck then
        -- Glued: down out of the air and still, but still watching.
        self.lift = math.max(0, self.lift - 60 * dt)
        self.squashTo = 0.08
        share = 0
    elseif self.mode == "walk" then
        self.breath = (self.breath + dt * 5) % (math.pi * 2)
        self.squashTo = 0.03 * sin(self.breath) -- breathing
        self.lift = 0
        self.modeT = self.modeT - dt
        if self.modeT <= 0 then
            if love.math.random() < 0.55 then
                self.mode, self.hops = "hop", love.math.random(HOPS[1], HOPS[2])
                self.phase, self.phaseT = "crouch", CROUCH
            else
                self.mode, self.phase, self.phaseT = "roll", "crouch", CROUCH * 1.5
            end
        end
    elseif self.mode == "hop" then
        self.phaseT = self.phaseT - dt
        local last = self.hops == 1
        if self.phase == "crouch" then
            share, self.squashTo = 0, last and 0.32 or 0.2
            if self.phaseT <= 0 then
                self.phase, self.phaseT = "air", AIR * (last and 1.25 or 1)
                self.squashV = self.squashV - (last and 4.2 or 3.2) -- spring up
            end
        elseif self.phase == "air" then
            local air = AIR * (last and 1.25 or 1)
            share = (CROUCH + air + SETTLE) / air
            local t = 1 - math.max(0, self.phaseT) / air
            self.lift = (last and LAST_HIGH or HOP_HIGH) * 4 * t * (1 - t)
            self.squashTo = t < 0.5 and -0.16 or -0.08
            if self.phaseT <= 0 then
                self.lift = 0
                self.squashV = self.squashV + (last and 6 or 4.2)
                self.thud = last and 2 or 1
                self.hops = self.hops - 1
                self.phase, self.phaseT = "settle", SETTLE
                if last then self.blinkP = math.max(self.blinkP, 0.001) end
            end
        else -- settle
            share, self.squashTo = 0, 0
            if self.phaseT <= 0 then
                if self.hops > 0 then
                    self.phase, self.phaseT = "crouch", CROUCH
                else
                    self.mode, self.modeT, self.phase = "walk", between(WALK), nil
                end
            end
        end
    elseif self.mode == "roll" then
        self.phaseT = self.phaseT - dt
        self.lift = 0
        if self.phase == "crouch" then
            share, self.squashTo = 0, 0.22
            if self.phaseT <= 0 then
                self.phase, self.phaseT = "roll", between(ROLL)
                self.squashV = self.squashV - 2.5
            end
        elseif self.phase == "roll" then
            share, rolling = ROLL_SPEED, true
            self.squashTo = 0.06
            if self.phaseT <= 0 then
                self.phase, self.phaseT = "dizzy", DIZZY
                self.squashV = self.squashV + 4
                self.thud = 1
            end
        else -- dizzy
            -- Pays back what the roll ran over, sat still and half shut while
            -- the turn spring brings the eye back round to you.
            share, self.squashTo = 0, 0
            self.squint = math.max(self.squint, 0.42)
            if self.phaseT <= 0 then
                self.mode, self.modeT, self.phase = "walk", between(WALK), nil
            end
        end
    end

    -- The turn: rolling, the frame turns by exactly what the ball travelled --
    -- about the axis lying on the page at right angles to the way it went, so
    -- going right spins it like a wheel and coming down the screen tips the
    -- front of it under. Otherwise it springs round to face you.
    if rolling then
        local r = RADIUS - RIM
        self.wx, self.wy, self.wz = -my / r / dt, 0, mx / r / dt
        self.skidT = self.skidT - dt
    else
        local dx, dy, dist = util.normalize(player.x - x, player.y - y)
        -- Now and then it glances off somewhere else for a beat: an eye that
        -- never moved except to follow you would be a turret.
        self.glanceT = self.glanceT - dt
        if self.glanceT <= 0 then
            if self.glanceX == 0 and self.glanceY == 0 and love.math.random() < 0.6 then
                local a = love.math.random() * math.pi * 2
                self.glanceX, self.glanceY = cos(a) * 0.45, sin(a) * 0.45
                self.glanceT = 0.25 + love.math.random() * 0.25
            else
                self.glanceX, self.glanceY = 0, 0
                self.glanceT = 0.9 + love.math.random() * 1.6
            end
        end
        local a = LOOK * math.min(1, dist / 24)
        local gx, gy = dx * a + self.glanceX, dy * a + self.glanceY
        local ga = sqrt(gx * gx + gy * gy)
        local tx, ty, tz = 0, 0, 1
        if ga > 1e-6 then
            local s = sin(ga) / ga
            tx, ty, tz = gx * s, gy * s, cos(ga)
        end
        self:track(dt, tx, ty, tz)
        -- The pupil opens up as you come close: it is looking at you.
        self.dilate = self.dilate + ((dist < 60 and 0.3 or 0) - self.dilate) * math.min(1, dt * 4)
    end
    self:spin(dt)

    -- The jelly.
    self.squashV = self.squashV + ((self.squashTo - self.squash) * SQUASH_K
        - self.squashV * SQUASH_C) * dt
    self.squash = math.max(SQUASH_MIN, math.min(SQUASH_MAX, self.squash + self.squashV * dt))

    -- Blinks, on their own uneven clock.
    self.blinkT = self.blinkT - dt
    if self.blinkT <= 0 and self.blinkP == 0 then
        self.blinkP = 0.001
        self.blinkT = 2.2 + love.math.random() * 3.5
    end
    if self.blinkP > 0 then
        self.blinkP = self.blinkP + dt / BLINK
        if self.blinkP >= 1 then self.blinkP = 0 end
    end
    self.squint = math.max(0, self.squint - dt * 1.6)
    self.pinch = math.max(0, self.pinch - dt * 2.5)

    return share
end

-- It fired: the pupil snaps shut to a point, the lid comes down into a glare
-- and the ball spits it out, stretched and then squashed. `big` is the ring.
function Eyeball:kick(big)
    self.pinch = big and 0.75 or 0.55
    self.squint = math.max(self.squint, big and 0.55 or 0.38)
    self.squashV = self.squashV - (big and 6 or 3)
end

-- It was hit: a shiver through the jelly, but only on top of a calm ball, since
-- a boss under fire is hit a dozen times a second and a spring kicked by every
-- one of them would just hum.
function Eyeball:jolt()
    if abs(self.squashV) < 1 then self.squashV = self.squashV + 1.2 end
end

-- What the gait threw up this frame, put on the page: dust kicked out either
-- side where it landed, a knock under the camera for the big one, and grit
-- thrown off the back of a roll.
function Eyeball:spill(game, e)
    local gy = e.y + RADIUS
    if self.thud then
        local n = self.thud == 2 and 10 or 5
        for _ = 1, n do
            game.particles:crumb(e.x, gy, 0, -1, RADIUS * (self.thud == 2 and 1.2 or 0.9),
                Palette.graphite)
        end
        if self.thud == 2 then Camera.knock(1) end
        self.thud = nil
    end
    if self.mode == "roll" and self.phase == "roll" and self.skidT <= 0 then
        self.skidT = 0.09
        local dx, dy = util.normalize(e.headX, e.headY)
        if dx ~= 0 or dy ~= 0 then
            game.particles:crumb(e.x - dx * RADIUS * 0.6, gy - 2, -dx, -dy, 4, Palette.graphite)
        end
    end
end

-- Where the outline is this frame: the centre and the two radii. Sat on the
-- ground -- the squash flattens it down onto its own bottom edge rather than
-- about its middle, which is the difference between landing and shrinking.
function Eyeball:frame(x, y)
    local rx, ry = self:radii()
    local cx = floor(x) + 0.5
    local gy = floor(y) + RADIUS + 1
    local cy = floor(gy - ry - self.lift + 0.5)
    return cx, cy, rx, ry
end

-- The span of row `j` (an integer pixel row) inside an ellipse, or nil.
local function span(cx, cy, rx, ry, j)
    local v = (j + 0.5 - cy) / ry
    if v <= -1 or v >= 1 then return end
    local half = rx * sqrt(1 - v * v)
    local x0 = floor(cx - half + 0.5)
    local x1 = floor(cx + half + 0.5)
    if x1 <= x0 then return end
    return x0, x1
end

-- The silhouette, `pad` pixels out, in whatever colour is set: the blank under
-- the body, the rim of a hit, the body blown out by a flash.
function Eyeball:drawMask(x, y, pad)
    local cx, cy, rx, ry = self:frame(x, y)
    rx, ry = rx + (pad or 0), ry + (pad or 0)
    for j = floor(cy - ry), floor(cy + ry) do
        local x0, x1 = span(cx, cy, rx, ry, j)
        if x0 then love.graphics.rectangle("fill", x0, j, x1 - x0, 1) end
    end
end

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local sky, blue, red = Palette.sky, Palette.blue, Palette.red

-- How far the lid has come down, 0 open and 1 shut: the blink's down-and-up
-- over whatever squint it is holding.
function Eyeball:lid()
    local b = 0
    if self.blinkP > 0 then b = 1 - abs(self.blinkP * 2 - 1) end
    return math.max(b, self.squint)
end

-- The ball, every pixel of it. Read top to bottom the questions are: is it the
-- rim; is it under the lid; then, turned into the ball's own frame, is it pupil,
-- iris or white; then is it in the light's shadow; then is it the catchlight.
function Eyeball:draw(x, y)
    local cx, cy, rx, ry = self:frame(x, y)
    local irx, iry = rx - RIM, ry - RIM
    local ax, ay, az = self.ax, self.ay, self.az
    local cosI = cos(IRIS)
    local cosL = cos(IRIS - LIMBUS)
    local cosC = cos(COLLAR)
    local cosP = cos(PUPIL * math.max(0.35, 1 + self.dilate - self.pinch))
    local veins = self.veins
    local fibre = 7 / math.pi

    -- The lid's edge as a height on the inner disc: off the top when open, past
    -- the bottom when shut, bowed down in the middle where it wraps the ball.
    local lid = self:lid()
    local edge = lid > 0 and -1.45 + lid * 2.2 or nil

    -- Written as runs of one colour along a row rather than a rectangle a
    -- pixel, so the ball is a few hundred fills rather than a couple of thousand.
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
                    local light = LX * su + LY * sv + LZ * sz
                    if edge and sv < edge + 0.4 * sz then
                        -- Under the lid. Its bottom row is the lash line.
                        local below = (j + 1.5 - cy) / iry
                        local bz = sqrt(math.max(0, 1 - su * su - below * below))
                        -- The lid is the same white skin as the ball, so a
                        -- blink reads as the eye shutting rather than as
                        -- something being put over it.
                        if below >= edge + 0.4 * bz then
                            colour = ink
                        elseif light < SHADE or (light < DITHER and (px + j) % 2 == 0) then
                            colour = graphite
                        else
                            colour = paper
                        end
                    else
                        -- Into the ball's frame: how far round towards where it
                        -- is looking this point is.
                        local bz = az[1] * su + az[2] * sv + az[3] * sz
                        local dark = light < SHADE
                            or (light < DITHER and (px + j) % 2 == 0)
                        if bz > cosP then
                            colour = ink
                        elseif bz > cosI then
                            if bz < cosL then
                                colour = blue
                            elseif bz < cosC then
                                local bx = ax[1] * su + ax[2] * sv + ax[3] * sz
                                local by = ay[1] * su + ay[2] * sv + ay[3] * sz
                                colour = floor(atan2(by, bx) * fibre) % 2 == 0 and blue or sky
                            else
                                colour = sky
                            end
                            if dark then colour = colour == sky and blue or slate end
                        else
                            colour = dark and graphite or paper
                            if bz < 0.8 and bz > -0.6 then
                                local bx = ax[1] * su + ax[2] * sv + ax[3] * sz
                                local by = ay[1] * su + ay[2] * sv + ay[3] * sz
                                local phi = atan2(by, bx)
                                local across = sqrt(1 - bz * bz) * irx
                                for k = 1, #veins do
                                    local v = veins[k]
                                    if bz < v.reach then
                                        local at = v.phi + v.wob * sin(bz * v.freq)
                                        local off = (phi - at + math.pi) % (math.pi * 2) - math.pi
                                        if abs(off) * across < 0.6
                                            or (v.fork and bz > v.fork
                                                and abs(off - (bz - v.fork) * 1.4) * across < 0.5) then
                                            colour = red
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        -- The catchlight, on the cornea and so painted over the
                        -- iris, the pupil and the white alike -- where it lands
                        -- on white it is white on white, which is right.
                        if HX * su + HY * sv + HZ * sz > GLINT then colour = paper end
                    end
                end
                put(px, j, colour)
            end
            flush(x1)
        end
    end
end

return Eyeball
