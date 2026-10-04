-- The eye boss's mind: what it does between walking at you, and when.
--
-- The eye had three ways of hurting you and all of them were clocks: a fan on a
-- beat, tears on two more, a trail on a fourth. Clocks are fair and they are
-- learnable, and after the second eye they are also all the fight is -- nothing
-- it did was ever a *decision*. This is the half that decides. Between glides it
-- picks one of four big moves off where you are and what you are doing, plays it
-- out in three beats that are always the same three -- a tell you can read, the
-- move, and a moment after it where it is open -- and then goes back to walking.
--
--  - **The stare.** It stops, glares, and a dotted line comes out of the iris
--    and swings round towards you; then it stops swinging, the line goes solid,
--    and a moment later the line is a beam. The 3D eye is the tell -- you can
--    see exactly where it is looking -- and the solid line is the promise: it
--    will not follow you off it. From the second phase the beam keeps sweeping
--    the way it was turning, so the answer is to step *against* the swing.
--  - **The bowl.** The wad's charge at the boss's size: a blinking red rim and
--    an arrow while it winds up, then it rolls down the line it locked at the
--    start, fast, smearing a wet streak behind it and bouncing off the walls of
--    the box -- none, once, then twice as the fight goes on. Then it sits dizzy.
--  - **The slam.** It crouches and leaps at where you are going to be, a
--    marker on the ground the whole time it is in the air, and lands in a ring
--    that rolls out across the floor. Being far enough away when it lands is the
--    whole answer; from the third phase it does it twice.
--  - **The sink.** It goes down into its own puddle and comes up out of another
--    one -- the trail it left stops being only ground you cannot stand on and
--    becomes ground it can come *out* of. Where it will surface bubbles for the
--    whole time it is under.
--  - **The weep.** From the second phase: it looks up, a tear wells, and it
--    throws rings of tears into the air round itself, each further out than the
--    last and turned so the gaps never line up. Every tear's shadow is on the
--    floor before it lands, so the way out is a zigzag through the gaps.
--
-- What makes it a mind rather than a sixth clock is the choosing. Every move is
-- weighted off the distance to you (a slam is for someone standing close, a
-- stare and a sink for someone keeping away), off how you are moving (it leads a
-- running target, never a still one), off whether it has got itself stuck (a
-- jammed eye goes underground), and away from whatever it did last -- the same
-- move twice in a row is a pattern you can stand in. And it gets meaner by
-- phase, at the same two thirds and one third the tear rings mark: shorter rests
-- between moves, more bounces, a sweep on the beam, a second slam -- and two of
-- the five moves, the sink and the weep, are not in its hand at all until the
-- first third of its health is gone. The first third is the fight taught in
-- three moves; the rest is the same fight with more of them.
--
-- Every move has a tell of at least half a second and every one of them is
-- answered by moving, which is the whole of this boss's design (Enemy.types):
-- nothing here is dodged by reflex, and nothing reaches you faster than you can
-- walk out of it once you have read it.
--
-- It also brings the boss on and takes it off, since both are the same body
-- being told what to do: it drops in from above the page on a marker, and when
-- it dies it shivers, rolls its eye up, and bursts into the puddles it was made
-- of (EyeBoss.fall).

local Palette = require("src.palette")
local Camera = require("src.camera")
local Eyeball = require("src.eyeball")
local Puddle = require("src.puddle")
local pixelart = require("src.pixelart")
local util = require("src.util")

local EyeBoss = {}
EyeBoss.__index = EyeBoss

local R = Eyeball.RADIUS
local LOOK = Eyeball.LOOK

-- The entrance: how high above the page it starts, how long the drop takes, and
-- how long it lies there with the eye shut before it opens on you.
local ENTER_HIGH, ENTER_TIME, WAKE_TIME = 170, 0.95, 0.75
local ENTER_DIST = 100 -- from you, so it never lands on you

-- The death: how long it shivers before it bursts, and how long the burst is
-- left on the page before the win card.
local FALL_POP, FALL_END = 0.9, 1.6

local STUCK_TIME, STUCK_MOVE = 1.6, 14 -- this little ground in this long is stuck

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function between(a, b) return a + love.math.random() * (b - a) end

local function lerpAngle(a, b, most)
    local d = (b - a + math.pi) % (math.pi * 2) - math.pi
    if math.abs(d) <= most then return b, d end
    return a + (d > 0 and most or -most), d
end

function EyeBoss.new(def)
    return setmetatable({
        def = def.attacks,
        state = "enter", t = 0,
        phase = 1,
        last = nil, before = nil, -- the last two moves, for not repeating them
        pvx = 0, pvy = 0,         -- how you are moving, smoothed
        anchorX = nil, anchorY = nil, anchorT = 0, stuck = false,
        shocks = {},
    }, EyeBoss)
end

-- Whether it is in the middle of something. The fan and the lane hold their
-- clocks while it is (Game:updateEnemies, Game:updateTears): a beam with a fan
-- fired across it is two things to read at once, and the whole promise of a tell
-- is that it is the one thing on the page that matters right now.
function EyeBoss:busy()
    return self.state ~= "idle"
end

-- The ground under it, which is where its feet are and where everything it
-- leaves on the floor goes.
local function feet(e) return e.x, e.y + R * 0.5 end

-- How hard it hits, scaled the way its contact damage was (Enemy.new): a move's
-- number on the row is the first cycle's, and the eye on the fourth hits harder.
local function scaled(e, damage) return damage * e.damage / e.def.damage end

function EyeBoss:update(dt, game, e)
    local eb = e.eyeball
    local player = game.player
    if dt <= 0 then return end

    -- How you are moving, smoothed over a few frames: what it leads you by.
    if self.px then
        local k = math.min(1, dt * 6)
        self.pvx = self.pvx + ((player.x - self.px) / dt - self.pvx) * k
        self.pvy = self.pvy + ((player.y - self.py) / dt - self.pvy) * k
    end
    self.px, self.py = player.x, player.y

    -- The phase, and the body's say of it: veins in, and the iris red at the
    -- last third. Ahead of everything so the move picked this frame is picked
    -- by the phase it is in.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        self:escalate(game, e)
    end
    eb.hurt = 1 - share
    eb.red = phase >= 3

    -- The lane's tell: a tear wells at the lid for the last moment before it.
    local lane = e.laneT
    eb.well = (lane and not self:busy() and lane < 0.7) and (1 - lane / 0.7) or 0

    self:updateShocks(dt, game)

    -- Glue answers a tell. A move it was still winding up is dropped on the
    -- spot and it goes straight to being open -- which is what a glueing should
    -- buy against a boss, and the one tool-shaped counterplay this fight has.
    if e.frozen > 0 and (self.state == "stareAim" or self.state == "stareLock"
        or self.state == "bowlWind" or self.state == "slamCrouch"
        or self.state == "sinkDown" or self.state == "weepWell") then
        self:open(e, 0.4, true)
    end

    self.t = self.t - dt
    self[self.state](self, dt, game, e)
end

-- The fight has turned. Said with the body rather than with words: it flinches
-- hard, shuts its eye, and the page knocks -- and at the last third the iris
-- comes back open red.
function EyeBoss:escalate(game, e)
    local eb = e.eyeball
    eb:kick(true)
    eb:blink()
    eb.squint = 1
    Camera.knock(self.phase >= 3 and 3 or 2)
    game.particles:burst(e.x, e.y, self.phase >= 3 and 30 or 16, Palette.red)
end

--- the entrance ---------------------------------------------------------------

function EyeBoss:enter(dt, game, e)
    local eb = e.eyeball
    if not self.from then
        -- Put down somewhere it can be seen coming: between you and wherever the
        -- spawner dropped it, far enough out that it never lands on you, and
        -- inside the box.
        local dx, dy = util.normalize(e.x - game.player.x, e.y - game.player.y)
        if dx == 0 and dy == 0 then dx, dy = 0, -1 end
        local x, y = game.player.x + dx * ENTER_DIST, game.player.y + dy * ENTER_DIST
        if game.arena then x, y = game.arena:clamp(x, y, R + 8) end
        e.x, e.y = x, y
        eb.lastX = nil
        self.from = true
        self.t = ENTER_TIME
        self.mark = { x = x, y = y, time = ENTER_TIME }
    end
    e.ghost = true
    e.hitCooldown = math.max(e.hitCooldown, 0.1)
    e.drive = { hold = true }
    local f = 1 - math.max(0, self.t) / ENTER_TIME
    eb.ctl = { lift = ENTER_HIGH * (1 - f * f), squash = -0.18, shut = 1 }
    if self.t <= 0 then
        e.ghost = false
        self.mark = nil
        eb.ctl = { lift = 0, squash = 0, shut = 1 }
        eb.squashV = eb.squashV + 8
        eb.thud = 3
        self:shock(game, e, 44, 0) -- dust, not a hit: it has not seen you yet
        self.state, self.t = "wake", WAKE_TIME
    end
end

-- Lying where it landed with the eye shut, then opening it on you.
function EyeBoss:wake(dt, game, e)
    local f = math.max(0, self.t) / WAKE_TIME
    e.drive = { hold = true }
    e.eyeball.ctl = { squash = 0.05, shut = f, dilate = 0.5 }
    if self.t <= 0 then self:idleFor(e, 1.0) end
end

--- walking about --------------------------------------------------------------

function EyeBoss:idleFor(e, t)
    self.state, self.t = "idle", t
    e.eyeball.ctl = nil
    e.chargePhase = nil
    e.drive = nil
    self.anchorX, self.anchorY, self.anchorT = e.x, e.y, 0
end

-- Open: stood still after a move, and the window the move paid for.
function EyeBoss:resting(dt, game, e)
    e.drive = { hold = true }
    e.eyeball.ctl = { squash = 0, shut = self.dizzy and 0.45 or 0 }
    if self.t <= 0 then
        local cool = self.def.cool
        self:idleFor(e, pick(cool, self.phase) + love.math.random() * 0.6)
    end
end

function EyeBoss:open(e, t, dizzy)
    self.state, self.t = "resting", t
    self.beam, self.aim, self.mark, self.bubbles = nil, nil, nil, nil
    e.eyeball.well = 0
    e.chargePhase = nil
    e.ghost = false
    e.eyeball.sink = 0
    self.dizzy = dizzy
end

-- Walking at you between moves -- at where you are going rather than where you
-- are, so running in a straight line away from it is running into its path --
-- and counting down to the next move.
function EyeBoss:idle(dt, game, e)
    local player = game.player
    e.drive = { seek = true, x = player.x + self.pvx * 0.6, y = player.y + self.pvy * 0.6 }
    if game.arena then e.drive.x, e.drive.y = game.arena:clamp(e.drive.x, e.drive.y, R) end

    -- Stuck: barely moved for a while, which is what being jammed against the
    -- box or a pen line or a crowd looks like. A stuck eye goes underground.
    self.anchorT = self.anchorT + dt
    if util.len(e.x - self.anchorX, e.y - self.anchorY) > STUCK_MOVE then
        self.anchorX, self.anchorY, self.anchorT, self.stuck = e.x, e.y, 0, false
    elseif self.anchorT > STUCK_TIME then
        self.stuck = true
    end

    if self.t <= 0 and e.frozen <= 0 then self:choose(game, e) end
end

-- The choice. Every move gets a weight off the situation, the last move and the
-- one before it are marked down hard, and one is drawn -- so it is never random
-- in a way that is stupid and never so predictable that it is a pattern.
function EyeBoss:choose(game, e)
    local player = game.player
    local d = util.len(player.x - e.x, player.y - e.y)
    local speed = util.len(self.pvx, self.pvy)
    local phase = self.phase
    local w = {}

    -- A beam for someone keeping their distance, and more so for someone
    -- running: a straight line away is a straight line to sweep across.
    w.stare = (d > 70 and 1.2 or 0.35) * (speed > 30 and 1.3 or 1)
    -- The bowl wants a lane: not on top of you and not across the box.
    w.bowl = (d > 45 and d < 190) and 1.1 or 0.3
    -- The slam is for whoever has come close to put damage in.
    w.slam = d < 95 and 1.6 or 0.6
    -- The sink needs somewhere to come up, and is what it does about being far
    -- from you or stuck.
    self.target = nil
    if phase >= self.def.sink.from then
        self.target = self:surfacing(game, e)
        if self.target then
            w.sink = (d > 130 and 1.4 or 0.6) * (self.stuck and 3 or 1)
        end
    end

    -- The weep is for someone in the middle distance, and more so for someone
    -- standing still: rings of rain are what being planted costs.
    if phase >= self.def.weep.from then
        w.weep = ((d > 45 and d < 170) and 1.0 or 0.45) * (speed < 20 and 1.5 or 1)
    end

    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.12 end
    if self.before and w[self.before] then w[self.before] = w[self.before] * 0.6 end

    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "stare"
    for _, name in ipairs({ "stare", "bowl", "slam", "sink", "weep" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.before, self.last = self.last, move
    self.stuck = false
    self[move .. "Start"](self, game, e)
end

--- the stare ------------------------------------------------------------------

-- Where the beam comes out of: the iris, on the near side of the ball along the
-- way it is aimed.
local function eyeAt(e, a)
    return e.x + math.cos(a) * 12, e.y + 1 + math.sin(a) * 10
end

-- How far the beam goes along `a` from (x, y): to the wall of the box, or a
-- long way on an open page.
local function reach(game, x, y, a, most)
    local dx, dy = math.cos(a), math.sin(a)
    local t = most
    local box = game.arena
    if box then
        if dx > 1e-6 then t = math.min(t, (box:right() - x) / dx) end
        if dx < -1e-6 then t = math.min(t, (box.left - x) / dx) end
        if dy > 1e-6 then t = math.min(t, (box:bottom() - y) / dy) end
        if dy < -1e-6 then t = math.min(t, (box.top - y) / dy) end
    end
    return math.max(0, t)
end

function EyeBoss:stareStart(game, e)
    local s = self.def.stare
    local toYou = math.atan2(game.player.y - e.y, game.player.x - e.x)
    -- It starts off to one side of you and swings round, so the line arrives
    -- rather than appears: you see it coming before it is on you.
    local side = love.math.random() < 0.5 and -1 or 1
    self.beam = { a = toYou + side * 0.8, firing = false, locked = false, turn = side }
    self.state, self.t = "stareAim", pick(s.aim, self.phase)
end

function EyeBoss:stareAim(dt, game, e)
    local s, beam, eb = self.def.stare, self.beam, e.eyeball
    local ox, oy = eyeAt(e, beam.a)
    local toYou = math.atan2(game.player.y - oy, game.player.x - ox)
    local d
    beam.a, d = lerpAngle(beam.a, toYou, s.turn * dt)
    if d ~= 0 then beam.turn = d > 0 and 1 or -1 end
    e.drive = { hold = true }
    eb.ctl = { squash = 0.08, look = { Eyeball.gaze(math.cos(beam.a), math.sin(beam.a), LOOK) },
        dilate = -0.4 }
    eb.squint = math.max(eb.squint, 0.4)
    if self.t <= 0 then
        -- It stops following you here, and the line goes solid to say so. The
        -- line you see for the lock is the line the beam comes down, to the
        -- pixel: tracking right up to the shot was a beam on you every time,
        -- and a tell you cannot act on is not one.
        beam.locked = true
        self.state, self.t = "stareLock", pick(s.lock, self.phase)
        self.lockTime = self.t
    end
end

function EyeBoss:stareLock(dt, game, e)
    local s, beam, eb = self.def.stare, self.beam, e.eyeball
    e.drive = { hold = true }
    -- Drawing itself up for it: squinting harder and squeezing down, so the
    -- body says "now" as the line does.
    local f = 1 - math.max(0, self.t) / self.lockTime
    eb.ctl = { squash = 0.08 + 0.12 * f, look = { Eyeball.gaze(math.cos(beam.a), math.sin(beam.a), LOOK) },
        dilate = -0.4 - 0.4 * f }
    eb.squint = math.max(eb.squint, 0.4 + 0.2 * f) -- never so shut you lose where it looks
    if self.t <= 0 then
        beam.firing = true
        self.state, self.t = "stareFire", pick(s.fire, self.phase)
        Camera.knock(2)
        eb:kick(false)
    end
end

function EyeBoss:stareFire(dt, game, e)
    local s, beam, eb = self.def.stare, self.beam, e.eyeball
    beam.a = beam.a + beam.turn * pick(s.sweep, self.phase) * dt
    e.drive = { hold = true }
    eb.ctl = { squash = -0.06, look = { Eyeball.gaze(math.cos(beam.a), math.sin(beam.a), LOOK) },
        dilate = 0.6 }

    local ox, oy = eyeAt(e, beam.a)
    local len = reach(game, ox, oy, beam.a, s.length)
    local ex, ey = ox + math.cos(beam.a) * len, oy + math.sin(beam.a) * len
    beam.x0, beam.y0, beam.x1, beam.y1 = ox, oy, ex, ey

    local player = game.player
    if util.distToSegment(player.x, player.y, ox, oy, ex, ey) < player.radius + s.width / 2 then
        if player:hurt(scaled(e, s.damage)) then
            game.particles:burst(player.x, player.y, 6, Palette.red)
        end
    end
    -- Where it hits the wall, it throws sparks.
    if love.math.random() < 0.5 then
        game.particles:burst(ex, ey, 1, love.math.random() < 0.5 and Palette.red or Palette.ink)
    end
    if self.t <= 0 then self:open(e, s.rest) end
end

--- the bowl -------------------------------------------------------------------

function EyeBoss:bowlStart(game, e)
    local b = self.def.bowl
    local p = game.player
    -- Locked here, at the start of the wind, and never looked at again: the
    -- wad's rule (Enemy:charge), and what makes it dodgeable. Leading you by a
    -- moment, so running straight is what it punishes.
    local tx, ty = p.x + self.pvx * b.lead, p.y + self.pvy * b.lead
    local dx, dy = util.normalize(tx - e.x, ty - e.y)
    if dx == 0 and dy == 0 then dx, dy = 1, 0 end
    self.aim = { dx = dx, dy = dy }
    self.bounces = 0
    self.state, self.t = "bowlWind", pick(b.wind, self.phase)
end

function EyeBoss:bowlWind(dt, game, e)
    local aim, eb = self.aim, e.eyeball
    e.drive = { hold = true }
    -- The wad's own blinking rim (Enemy:outlineColour), borrowed rather than
    -- copied: the one red warning the game already teaches.
    e.chargePhase, e.phaseT = "wind", math.max(0, self.t)
    eb.ctl = { squash = 0.26, look = { Eyeball.gaze(aim.dx, aim.dy, LOOK) } }
    if self.t <= 0 then
        self.aim = nil
        self.dash = { dx = aim.dx, dy = aim.dy }
        self.state, self.t = "bowlRoll", self.def.bowl.time
        self.stall = 0
        eb.squashV = eb.squashV - 4
    end
end

function EyeBoss:bowlRoll(dt, game, e)
    local b, dash, eb = self.def.bowl, self.dash, e.eyeball
    e.chargePhase = "dash"

    -- Off the walls of the box: read off where the clamp left it last frame
    -- (Game:updateEnemies clamps after the move), so a bounce is the box saying
    -- no rather than this guessing where the box is.
    local box = game.arena
    local hit = false
    if box then
        local pad = e.radius + 0.5
        if dash.dx < 0 and e.x <= box.left + pad then dash.dx, hit = -dash.dx, true end
        if dash.dx > 0 and e.x >= box:right() - pad then dash.dx, hit = -dash.dx, true end
        if dash.dy < 0 and e.y <= box.top + pad then dash.dy, hit = -dash.dy, true end
        if dash.dy > 0 and e.y >= box:bottom() - pad then dash.dy, hit = -dash.dy, true end
    end
    -- And off anything else that stops it dead, which is a pen line: there is
    -- no wall to bounce off, so it just stops.
    if self.lastX and util.len(e.x - self.lastX, e.y - self.lastY) < b.speed * dt * 0.25 then
        self.stall = self.stall + 1
    else
        self.stall = 0
    end
    self.lastX, self.lastY = e.x, e.y

    if hit then
        self.bounces = self.bounces + 1
        eb.thud = 3
        eb.squashV = eb.squashV + 6
    end
    if (hit and self.bounces > pick(b.bounces, self.phase)) or self.stall >= 4 or self.t <= 0 then
        if not hit then eb.thud = 1 end
        self.dash, self.lastX = nil, nil
        self:open(e, b.rest, true)
        return
    end

    e.drive = { dash = true, dx = dash.dx, dy = dash.dy, speed = b.speed }
    eb.ctl = { rolling = true, squash = 0.04 }
end

--- the slam -------------------------------------------------------------------

function EyeBoss:slamStart(game, e)
    self.leaps = pick(self.def.slam.leaps, self.phase)
    self.state, self.t = "slamCrouch", self.def.slam.crouch
end

function EyeBoss:slamCrouch(dt, game, e)
    local s, eb, p = self.def.slam, e.eyeball, game.player
    e.drive = { hold = true }
    local dx, dy = util.normalize(p.x - e.x, p.y - e.y)
    eb.ctl = { squash = 0.32, look = { Eyeball.gaze(dx, dy, LOOK) } }
    if self.t <= 0 then
        -- Where it is going to come down: where you will be half way through
        -- its flight if you keep doing what you are doing, no further than it
        -- can jump, and inside the box. Decided here, at take-off, and marked
        -- on the floor for the whole time it is in the air.
        local tx = p.x + self.pvx * s.air * 0.5
        local ty = p.y + self.pvy * s.air * 0.5
        local ox, oy = tx - e.x, ty - e.y
        local d = util.len(ox, oy)
        if d > s.reach then tx, ty = e.x + ox / d * s.reach, e.y + oy / d * s.reach end
        if game.arena then tx, ty = game.arena:clamp(tx, ty, R) end
        self.fromX, self.fromY, self.toX, self.toY = e.x, e.y, tx, ty
        self.mark = { x = tx, y = ty, time = s.air }
        self.state, self.t = "slamAir", s.air
        eb.squashV = eb.squashV - 6
    end
end

function EyeBoss:slamAir(dt, game, e)
    local s, eb = self.def.slam, e.eyeball
    local f = 1 - math.max(0, self.t) / s.air
    -- Placed rather than walked: a leap goes where it was aimed whatever the
    -- crowd is doing underneath it. The box clamp still has the last word.
    e.x = self.fromX + (self.toX - self.fromX) * f
    e.y = self.fromY + (self.toY - self.fromY) * f
    e.drive = { hold = true }
    -- Over the crowd's heads, so nothing touches it and it touches nothing.
    e.hitCooldown = math.max(e.hitCooldown, 0.1)
    -- Tumbling: the frame turns by the ground it crosses, so a long leap is a
    -- somersault and it comes down looking at you again off the turn spring.
    eb.ctl = { lift = s.high * 4 * f * (1 - f), squash = f < 0.5 and -0.2 or -0.1, tumble = true }
    if self.t <= 0 then
        self.mark = nil
        eb.ctl = { lift = 0, squash = 0 }
        eb.squashV = eb.squashV + 8
        eb.thud = 3
        self:shock(game, e, pick(s.shock, self.phase), scaled(e, s.damage))
        local ring = pick(s.ring, self.phase)
        if ring > 0 and e.def.tears then
            local turn = love.math.random() * math.pi * 2
            for i = 0, ring - 1 do
                game:throwTear(e, e.def.tears, turn + i * math.pi * 2 / ring, s.tearReach)
            end
        end
        self.leaps = self.leaps - 1
        if self.leaps > 0 then
            self.state, self.t = "slamCrouch", s.crouch * 0.75
        else
            self:open(e, s.rest, true)
        end
    end
end

--- the sink -------------------------------------------------------------------

-- Where it could come up: one of the page's wet blots that is not about to dry,
-- well away from where it is, and at a middling distance from you -- not under
-- your feet, which would be a hit nobody could have seen coming, and not so far
-- that it is running away. The one nearest to the distance it wants wins.
function EyeBoss:surfacing(game, e)
    local s = self.def.sink
    local p = game.player
    local best, bestScore
    for _, pd in ipairs(game.puddles) do
        if pd.damage > 0 and pd.life - pd.age > s.down + s.under + s.up + 1 then
            local dYou = util.len(pd.x - p.x, pd.y - p.y)
            local dMe = util.len(pd.x - e.x, pd.y - e.y)
            if dYou >= s.near and dYou <= s.far and dMe > 70
                and (not game.arena or game.arena:contains(pd.x, pd.y)) then
                local score = math.abs(dYou - (s.near + s.far) / 2)
                if not bestScore or score < bestScore then best, bestScore = pd, score end
            end
        end
    end
    return best
end

function EyeBoss:sinkStart(game, e)
    local s = self.def.sink
    local pd = self.target
    self.target = nil
    -- Where it will come up, held as a point rather than as the puddle, since
    -- the puddle may dry while it is under.
    self.bubbles = { x = pd.x, y = pd.y, r = math.max(8, pd.r) }
    local x, y = feet(e)
    Eyeball.splat(game, e, x, y, e.def.trail.radius * 1.2, 4)
    self.state, self.t = "sinkDown", s.down
end

function EyeBoss:sinkDown(dt, game, e)
    local s, eb = self.def.sink, e.eyeball
    local f = 1 - math.max(0, self.t) / s.down
    e.drive = { hold = true }
    eb.ctl = { squash = 0.1 * f, shut = f * 0.8 }
    eb.sink = f * f
    if self.t <= 0 then
        eb.sink = 1
        e.ghost = true
        self.state, self.t = "sinkUnder", s.under
    end
end

function EyeBoss:sinkUnder(dt, game, e)
    local s, eb = self.def.sink, e.eyeball
    e.drive = { hold = true }
    e.hitCooldown = math.max(e.hitCooldown, 0.1)
    eb.ctl = { shut = 1 }
    eb.sink = 1
    if self.t <= 0 then
        local b = self.bubbles
        e.x, e.y = b.x, b.y - R * 0.5
        if game.arena then e.x, e.y = game.arena:clamp(e.x, e.y, e.radius) end
        eb.lastX = nil
        e.ghost = false
        self.state, self.t = "sinkUp", s.up
    end
end

function EyeBoss:sinkUp(dt, game, e)
    local s, eb = self.def.sink, e.eyeball
    local f = 1 - math.max(0, self.t) / s.up
    e.drive = { hold = true }
    local dx, dy = util.normalize(game.player.x - e.x, game.player.y - e.y)
    eb.ctl = { squash = -0.15, shut = 1 - f, look = { Eyeball.gaze(dx, dy, LOOK) } }
    eb.sink = (1 - f) * (1 - f)
    if self.t <= 0 then
        eb.sink = 0
        eb.squashV = eb.squashV + 6
        eb.thud = 2
        local ring = pick(s.ring, self.phase)
        if ring > 0 and e.def.tears then
            local turn = love.math.random() * math.pi * 2
            for i = 0, ring - 1 do
                game:throwTear(e, e.def.tears, turn + i * math.pi * 2 / ring, s.tearReach)
            end
        end
        self:open(e, s.rest)
    end
end

--- the weep -------------------------------------------------------------------

function EyeBoss:weepStart(game, e)
    local w = self.def.weep
    self.volleys, self.volley = pick(w.volleys, self.phase), 0
    self.weepTurn = love.math.random() * math.pi * 2
    self.state, self.t = "weepWell", w.well
end

-- Looking up at nothing, with a tear swelling at the lid: the one move it makes
-- without looking at you, which is the tell -- an eye that has stopped watching
-- you is about to do something to the whole floor.
function EyeBoss:weepWell(dt, game, e)
    local w, eb = self.def.weep, e.eyeball
    local f = 1 - math.max(0, self.t) / w.well
    e.drive = { hold = true }
    eb.ctl = { squash = 0.12 + 0.14 * f, look = { Eyeball.gaze(0, -1, LOOK) }, dilate = 0.3 }
    eb.well = f
    if self.t <= 0 then self.state, self.t = "weepCry", 0 end
end

function EyeBoss:weepCry(dt, game, e)
    local w, eb = self.def.weep, e.eyeball
    e.drive = { hold = true }
    eb.ctl = { squash = -0.04, look = { Eyeball.gaze(0, -1, LOOK) }, dilate = 0.5 }
    eb.well = 0
    if self.t > 0 then return end
    self.volley = self.volley + 1
    local n = pick(w.count, self.phase)
    -- Each ring half a gap round from the last, so no hole lines up with the one
    -- inside it: walking straight out is walking into a tear.
    local turn = self.weepTurn + self.volley * math.pi / n
    local dist = w.near + (self.volley - 1) * w.step
    for i = 0, n - 1 do
        game:throwTear(e, e.def.tears, turn + i * math.pi * 2 / n, dist)
    end
    eb:kick(false)
    eb.squashV = eb.squashV - 3
    if self.volley >= self.volleys then
        self:open(e, w.rest)
    else
        self.t = w.gap
    end
end

--- the shockwave --------------------------------------------------------------

-- A ring rolling out across the floor from (x, y) to `most`, hitting you once if
-- it passes under you. `damage` 0 is dust and hits nobody.
function EyeBoss:shock(game, e, most, damage)
    local x, y = feet(e)
    self.shocks[#self.shocks + 1] = { x = x, y = y, r = 2, most = most, damage = damage }
end

local SHOCK_SPEED = 170

function EyeBoss:updateShocks(dt, game)
    local player = game.player
    for i = #self.shocks, 1, -1 do
        local s = self.shocks[i]
        s.r = s.r + SHOCK_SPEED * dt
        if s.damage > 0 and not s.hit then
            local d = util.len(player.x - s.x, player.y - s.y)
            if d < s.r + player.radius and d > s.r - 8 - player.radius then
                s.hit = true
                if player:hurt(s.damage) then
                    game.particles:burst(player.x, player.y, 6, Palette.red)
                end
            end
        end
        if s.r >= s.most then table.remove(self.shocks, i) end
    end
end

--- drawing --------------------------------------------------------------------

-- A dashed line marching from (x0, y0) along `a` for `len` pixels: the tell for
-- anything that will come down a line. The dashes walk outwards, so the line
-- reads as *going* somewhere.
local function dashes(x0, y0, a, len, phase, on)
    local dx, dy = math.cos(a), math.sin(a)
    on = on or 3
    for i = 0, math.floor(len) do
        if math.floor((i - phase) / on) % 2 == 0 then
            love.graphics.rectangle("fill", math.floor(x0 + dx * i), math.floor(y0 + dy * i), 1, 1)
        end
    end
end

-- On the page, under the crowd: the marker where it is going to land, and the
-- bubbles where it is going to come up.
function EyeBoss:drawGround(time)
    local m = self.mark
    if m then
        local f = 1 - math.max(0, self.t) / m.time
        local x, y = math.floor(m.x), math.floor(m.y + R * 0.6)
        -- Its shadow arriving: a smear that widens as it comes down...
        love.graphics.setColor(Palette.graphite)
        local w = math.floor(6 + f * 28)
        for k = -1, 1 do
            local ww = w - math.abs(k) * 6
            if ww > 0 then love.graphics.rectangle("fill", x - math.floor(ww / 2), y + k, ww, 1) end
        end
        -- ...inside a ring it will fill, blinking quicker as it gets close.
        if math.floor(time * (6 + f * 14)) % 2 == 0 then
            love.graphics.setColor(Palette.red)
            for k = 0, 35 do
                if k % 3 ~= 2 then
                    local ang = k / 36 * math.pi * 2
                    love.graphics.rectangle("fill", x + math.floor(math.cos(ang) * 22 + 0.5),
                        y + math.floor(math.sin(ang) * 8 + 0.5), 1, 1)
                end
            end
        end
    end

    local b = self.bubbles
    if b then
        -- Bubbles coming up through the wet, popping and coming again: rings
        -- in ink at spots that move on every eighth of a second, so they read
        -- against the pink of the puddle they are coming up through...
        local beat = math.floor(time * 8)
        for k = 1, 7 do
            local h1 = util.hash01(k, beat, 31)
            local h2 = util.hash01(k, beat, 37)
            local bx = math.floor(b.x + (h1 - 0.5) * b.r * 1.6)
            local by = math.floor(b.y + (h2 - 0.5) * b.r)
            local r = (k + beat) % 3 == 0 and 2 or 1
            love.graphics.setColor(Palette.ink)
            pixelart.circleOutline(bx, by, r)
            love.graphics.setColor(Palette.paper)
            love.graphics.rectangle("fill", bx - 1, by - r, 1, 1)
        end
        -- ...inside the same blinking ring the landing marker wears, since it is
        -- the same message: something big is about to be standing here.
        if math.floor(time * 12) % 2 == 0 then
            love.graphics.setColor(Palette.red)
            for k = 0, 35 do
                if k % 3 ~= 2 then
                    local ang = k / 36 * math.pi * 2
                    love.graphics.rectangle("fill",
                        math.floor(b.x + math.cos(ang) * 22 + 0.5),
                        math.floor(b.y + math.sin(ang) * 9 + 0.5), 1, 1)
                end
            end
        end
    end
end

-- Over the crowd: the stare's line and beam, the bowl's arrow, the rings.
function EyeBoss:drawAir(time, e)
    local beam = self.beam
    if beam and e then
        local ox, oy = eyeAt(e, beam.a)
        if beam.firing and beam.x1 then
            -- Hot: red with a white-hot core, and a flare where it hits.
            love.graphics.setColor(Palette.red)
            pixelart.band(beam.x0, beam.y0, beam.x1, beam.y1, self.def.stare.width)
            pixelart.circleFill(beam.x1, beam.y1, 3)
            love.graphics.setColor(Palette.paper)
            pixelart.band(beam.x0, beam.y0, beam.x1, beam.y1, 1)
            pixelart.circleFill(beam.x0, beam.y0, 2)
        else
            -- The tell: graphite dashes marching out while it is still
            -- following you, and a solid red line once it has stopped -- the
            -- line the beam will come down, held still long enough to step off.
            local len = 230
            if beam.locked then
                love.graphics.setColor(Palette.red)
                local ex, ey = ox + math.cos(beam.a) * len, oy + math.sin(beam.a) * len
                pixelart.line(math.floor(ox), math.floor(oy), math.floor(ex), math.floor(ey))
            else
                love.graphics.setColor(math.floor(time * 10) % 2 == 0 and Palette.red or Palette.slate)
                dashes(ox, oy, beam.a, len, time * 40)
            end
        end
    end

    local aim = self.aim
    if aim and e then
        -- The bowl's arrow: the lane it is about to take, out to a short way.
        love.graphics.setColor(Palette.red)
        local a = math.atan2(aim.dy, aim.dx)
        dashes(e.x + aim.dx * (R + 4), e.y + aim.dy * (R + 4), a, 70, time * 30, 4)
        local tx, ty = e.x + aim.dx * (R + 76), e.y + aim.dy * (R + 76)
        for _, side in ipairs({ -1, 1 }) do
            local b = a + math.pi * 0.8 * side
            pixelart.line(math.floor(tx), math.floor(ty),
                math.floor(tx + math.cos(b) * 6), math.floor(ty + math.sin(b) * 6))
        end
    end

    for _, s in ipairs(self.shocks) do
        love.graphics.setColor(s.damage > 0 and Palette.red or Palette.graphite)
        pixelart.circleOutline(math.floor(s.x), math.floor(s.y), math.floor(s.r))
        if s.r > 4 then
            love.graphics.setColor(s.damage > 0 and Palette.blush or Palette.graphite)
            pixelart.circleOutline(math.floor(s.x), math.floor(s.y), math.floor(s.r) - 3)
        end
    end
end

--- the death ------------------------------------------------------------------

-- What is left of the eye once it is killed: the body, taken off the enemy and
-- played out on its own for a beat and a half before the win card. It shivers
-- with its eye rolled up and its pupil blown, squashes flat, and bursts into the
-- puddles it was made of. None of those puddles hurt -- the fight is over and
-- the page should say so -- and nothing else can hurt you while it plays
-- (`truce`, Player:hurt), since a win you could die inside would not be one.
local Fall = {}
Fall.__index = Fall

function EyeBoss.fall(e)
    e.eyeball.sink, e.eyeball.well = 0, 0
    return setmetatable({ eb = e.eyeball, x = e.x, y = e.y, t = 0, def = e.def,
        reach = e.reach }, Fall)
end

function Fall:update(dt, game)
    self.t = self.t + dt
    local eb, t = self.eb, self.t
    if not self.popped then
        eb.shake = 1
        eb.ctl = {
            look = { 0, -0.94, 0.34 }, -- rolled up into its head
            dilate = 0.9,
            squash = t < 0.55 and 0.04 or 0.55,
            squashMax = 0.6,
            shut = t > 0.6 and math.min(0.55, (t - 0.6) * 2.5) or 0,
        }
        eb:update(dt, self.x, self.y, game.player, false)
        if t >= FALL_POP then self:pop(game) end
    end
    return t < FALL_END
end

function Fall:pop(game)
    self.popped = true
    local x, y = self.x, self.y + R * 0.4
    local trail = self.def.trail
    for i = 1, 9 do
        local a = i / 9 * math.pi * 2 + love.math.random() * 0.4
        local d = 10 + love.math.random() * 26
        local p = Puddle.new(x + math.cos(a) * d, y + math.sin(a) * d * 0.7, {
            radius = trail.radius * (0.5 + love.math.random() * 0.6),
            life = trail.life, drops = 4,
            stretch = 1.4, dx = math.cos(a), dy = math.sin(a),
        }, 0, love.math.random(2 ^ 20), self.reach)
        p:ripple()
        game.puddles[#game.puddles + 1] = p
    end
    local big = Puddle.new(x, y, { radius = trail.radius * 1.4, life = trail.life, drops = 8 },
        0, love.math.random(2 ^ 20), self.reach)
    big:ripple()
    game.puddles[#game.puddles + 1] = big
    game.particles:burst(self.x, self.y, 40, Palette.red)
    game.particles:burst(self.x, self.y, 30, Palette.ink)
    game.particles:burst(self.x, self.y, 20, Palette.blue)
    for _ = 1, 16 do game.particles:crumb(self.x, self.y + R, nil, nil, R, Palette.graphite) end
    Camera.knock(5)
end

function Fall:draw()
    if self.popped then return end
    -- Flickering white on and off as it goes, the hit flash it never comes
    -- back from.
    local x, y = self.x, self.y
    if math.floor(self.t / 0.07) % 3 == 0 then
        love.graphics.setColor(Palette.red)
        self.eb:drawMask(x, y, 1)
        love.graphics.setColor(Palette.paper)
        self.eb:drawMask(x, y, 0)
    else
        self.eb:draw(x, y)
    end
end

function Fall:drawSolid()
    if self.popped then return end
    love.graphics.setColor(Palette.paper)
    self.eb:drawMask(self.x, self.y, 1)
end

return EyeBoss
