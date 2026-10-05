-- What is left of a boss once it is killed, for every boss but the eye (which
-- comes apart its own way, EyeBoss.fall). Until this existed, the other nine went
-- off the page in the frame they were killed: a puff of blue specks and the win
-- card, so the hit that ended a ten-minute fight looked exactly like the hit
-- that ended a skull. This is the beat between the two.
--
-- The body itself is kept and drawn where it died, through its own Enemy:draw,
-- so every boss comes apart as itself -- the die on the face it was showing, the
-- stamp in the pose it was caught in, the metronome with its arm where it was --
-- and nothing here has to know how any of them is painted. It shivers, harder
-- as it goes, flickering through the hit flash it never comes back from (the
-- same blush-then-paper stages, the same red rim, faster and faster), spitting
-- specks; then it bursts into its own colours, a ring or two rolls out across
-- the floor, and the page says its last word. Nothing hurts you while that
-- plays (`truce`, Player:hurt), for the eye's reason: a win you could die inside
-- would not be one.
--
-- What each boss bursts into is a row on its own entry (`wreck` in
-- src/enemy.lua): the colours, how many rings, the sound and the last word. A
-- boss with no row gets the defaults and still comes apart.

local Camera = require("src.camera")
local Palette = require("src.palette")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")

local Wreck = {}
Wreck.__index = Wreck

-- How long it shivers before it bursts, and how long after that the burst is
-- left on the page before the win card. The eye's own numbers (FALL_POP,
-- FALL_END in src/eyeboss.lua), so every fight ends to the same count.
local POP, DONE = 0.9, 1.6

-- The flicker: seconds per step of the flash at the start, and at the burst.
-- Three steps to a cycle (its own colours, blush, paper), so it goes from a
-- slow pulse to a strobe.
local FLICK_SLOW, FLICK_FAST = 0.11, 0.035

-- How far it shakes, in whole pixels, at the start and at the burst.
local SHAKE_LO, SHAKE_HI = 1, 3

-- The rings rolled out by the burst: how far, how long, and how far apart in
-- time when there is more than one.
local RING_REACH, RING_TIME, RING_GAP = 70, 0.5, 0.12

-- The flash values that ask Enemy:draw for its blush stage and its paper stage
-- (HIT_FLASH and HIT_WHITE in src/enemy.lua: paper above 0.08, blush below).
local BLUSH, PAPER = 0.05, 0.12

local DEFAULT = { ink = { "red", "ink", "blue" }, rings = 1 }

function Wreck.new(e)
    -- Whatever it was in the middle of stops showing: a breath it was drawing
    -- for a blast, a recoil, the blast still going out.
    e.blowT, e.blareT, e.bumpT, e.flash = 0, 0, 0, 0
    return setmetatable({
        e = e, x = e.x, y = e.y, hop = e.hop or 0,
        t = 0, step = 0, spitT = 0,
        row = e.def.wreck or DEFAULT,
    }, Wreck)
end

function Wreck:colour(k)
    local ink = self.row.ink or DEFAULT.ink
    return Palette[ink[(k - 1) % #ink + 1]]
end

function Wreck:update(dt, game)
    -- Whatever the boss had standing in the horde for parts of it (the red pen's
    -- barrel, src/redpenboss.lua) is taken off the page here, on the first frame
    -- after the kill. Not in the kill itself: that can land inside any walk of
    -- the horde, and the walk is in depth order by then, so a part can be at an
    -- index under the one being walked -- taking it out would shift the list
    -- under the walk's feet. This runs after every walk has finished.
    if not self.swept then
        self.swept = true
        local brain = self.e.brain
        if brain and brain.sweep then brain:sweep(game) end
    end
    self.t = self.t + dt
    if self.popped then return self.t < DONE end

    local e, f = self.e, math.min(1, self.t / POP)
    -- Down out of whatever leap it was killed in, quickly: it is not going
    -- anywhere now, and a body hanging in the air over its own shadow for a
    -- second and a half would read as a thing still in the fight.
    e.hop = self.hop * math.max(0, 1 - self.t / 0.2)

    -- The flicker speeds up towards the burst.
    self.step = self.step + dt / (FLICK_SLOW + (FLICK_FAST - FLICK_SLOW) * f)

    -- And it spits, faster too: a few specks off its edge in its own colours.
    self.spitT = self.spitT - dt
    if self.spitT <= 0 then
        self.spitT = 0.16 - 0.11 * f
        local a = love.math.random() * math.pi * 2
        local r = e.radius * 0.8
        game.particles:burst(self.x + math.cos(a) * r, self.y + math.sin(a) * r - self:lift(),
            3, self:colour(love.math.random(1, 3)))
    end

    if self.t >= POP then self:pop(game) end
    return true
end

-- How far up off its shadow the body is drawn, so the bursts come out of the
-- body rather than out of the floor under it.
function Wreck:lift()
    return self.e.hop or 0
end

function Wreck:pop(game)
    self.popped = true
    self.t = POP
    local e, row = self.e, self.row
    e.x, e.y = self.x, self.y
    local x, y = self.x, self.y - self:lift()
    for k, n in ipairs({ 40, 30, 20 }) do game.particles:burst(x, y, n, self:colour(k)) end
    for _ = 1, 20 do game.particles:crumb(x, y, nil, nil, e.radius, Palette.graphite) end
    for k = 1, 8 do game.particles:crumb(x, y, nil, nil, e.radius, self:colour(k)) end
    Camera.knock(5)
    Sfx.play(row.sound or "stamp")
end

-- Shaking: a whole pixel or more either side, flipped on its own little clock
-- rather than rolled, so it reads as a shudder and not as noise.
function Wreck:shake()
    local f = math.min(1, self.t / POP)
    local amp = math.floor(SHAKE_LO + (SHAKE_HI - SHAKE_LO) * f + 0.5)
    local side = math.floor(self.t * 30) % 2 == 0 and 1 or -1
    return amp * side
end

-- The flash stage this frame: its own colours, blush, or paper.
function Wreck:flash()
    local k = math.floor(self.step) % 3
    return k == 1 and BLUSH or k == 2 and PAPER or 0
end

function Wreck:drawSolid()
    if self.popped then return end
    local e = self.e
    e.x, e.flash = self.x + self:shake(), self:flash()
    e:drawSolid()
    e.x = self.x
end

function Wreck:draw()
    if not self.popped then
        local e = self.e
        e.x, e.flash = self.x + self:shake(), self:flash()
        e:draw()
        e.x = self.x
        return
    end

    -- The rings out of the burst, stepping down a colour as they go rather than
    -- fading: the first of its colours, then graphite for the last stretch.
    local rings = self.row.rings or DEFAULT.rings
    local x, y = math.floor(self.x), math.floor(self.y)
    for k = 0, rings - 1 do
        local f = (self.t - POP - k * RING_GAP) / RING_TIME
        if f > 0 and f < 1 then
            love.graphics.setColor(f < 0.65 and self:colour(1) or Palette.graphite)
            pixelart.circleOutline(x, y, math.floor(self.e.radius + f * RING_REACH))
        end
    end
end

return Wreck
