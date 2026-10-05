-- The speaker's mind: MUSIC's encore, and the fight in the book about *volume*.
--
-- The metronome is a fight about when. The speaker is what the music is played
-- out of once the practising is over: a cylindrical bluetooth speaker, turned up
-- too far, and its fight is about how loud -- about sound as a thing that goes
-- out across the page and shoves. It keeps a beat too, because everything that
-- plays music does, but its beat is not a count-in to read. It is a groove to
-- move to: it bounces on it, its radiator pumps on it, its ring of lights
-- chases round on it, and from the last third every bar of it hurts.
--
-- **The drop.** Its signature, and a build-up the whole page can hear: a bar of
-- it stretching taller, its lights red and blinking faster, the ticks rising
-- and doubling up -- and then DROP!, it squashes flat and the bass goes out of
-- it as a ring across the whole box, one a beat for a bar or two. Every ring has
-- a quiet gap in it, drawn on the floor in your blue as a wedge before the ring
-- that carries it is let go, and the gap steps round it one way a beat at a time.
-- The way through a drop is to dance: round it, with the gap. At the last third
-- the beat switches half way and the gap goes back the other way.
--
-- **The roll.** A can rolls. It plants, shows you the lane with a dashed red
-- arrow and a blinking rim (the wad's tell, borrowed), tips over onto its side
-- and goes, far faster than you, off the walls of the box, bowling the crowd out
-- of the way -- and has to stand itself back up at the end, which is the window.
--
-- **The shuffle.** It spins, and spits a handful of notes out of its top that do
-- not stop at the walls: they bounce round the box like a screensaver until
-- they run out. Two handfuls at the last third.
--
-- **Pairing**, from the second phase, when the crowd is about: it turns its
-- back to show you the rune, its lights go blue, and it pairs with the nearest
-- few of the escort -- a link drawn to each, and a red ring round each where it
-- is about to go off. On the beat they all play at once. Kill a paired thing
-- first and it is disconnected; walk away from them and it is a crowd going
-- bang somewhere you are not. The one move in the book whose bullets are the
-- crowd.
--
-- **Glue mutes it.** Its lights go out and its beat stops while it is held, and
-- a drop, a roll, a shuffle or a pairing still being counted in is dropped --
-- the tool-shaped counterplay every boss in the book has, and the most
-- obvious one this one could have.
--
-- The body is src/speaker.lua, painted every frame; this file keeps the beat,
-- squashes, tips and rolls the body on it, and owns everything it lets go of:
-- the rings, the notes and the pairings.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local Sprites = require("src.sprites")
local pixelart = require("src.pixelart")
local util = require("src.util")

local SpeakerBoss = {}
SpeakerBoss.__index = SpeakerBoss

local TAU = math.pi * 2
local floor, abs, max, min, cos, sin = math.floor, math.abs, math.max, math.min, math.cos, math.sin

-- The entrance: dropped onto the page (Game:dropIn), then switched on -- its
-- lights coming up one at a time, a rising chime, and the first beat.
local ENTER_TIME = 1.2
-- How long the cosmetic puff round its foot on a beat, and a floating note, last.
local PUFF_TIME, FLOAT_TIME = 0.28, 0.9
-- How long a paired thing's blast, and the last third's thump, are drawn going out.
local BLAST_TIME = 0.22

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

-- The smallest angle between two headings, either way round.
local function apart(a, b) return abs((a - b + math.pi) % TAU - math.pi) end

function SpeakerBoss.new(def)
    return setmetatable({
        def = def.speaker,
        state = "enter", t = ENTER_TIME,
        phase = 1,
        last = nil,
        -- The beat: beats since it was switched on, and the last whole one it
        -- has acted on.
        clock = 0, beat = 0,
        waves = {},   -- the rings going out of it
        notes = {},   -- the shuffle's notes, bouncing round the box
        puffs = {},   -- what the beat puts on the page and in the air, harmless
        floats = {},
        blasts = {},  -- a paired thing going off, or a thump, drawn going out
        drop = nil, aim = nil, paired = nil,
        plusT = 0,
        e = nil,
    }, SpeakerBoss)
end

function SpeakerBoss:busy()
    return self.state ~= "idle"
end

--- the loop -------------------------------------------------------------------

function SpeakerBoss:update(dt, game, e)
    self.e = e
    local body = e.speaker
    if dt <= 0 then return end
    local def = self.def

    -- The phase, at the eye's thirds, and said out loud: it turns itself up.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        game:say(phase >= 3 and "VOLUME MAX!" or "VOLUME UP!")
        self.plusT = 1.0
        game.particles:burst(e.x, e.y - 12, phase >= 3 and 30 or 16, Palette.red)
        Camera.knock(phase >= 3 and 4 or 2)
        Sfx.play("accept", 0.7 + phase * 0.15)
    end
    self.plusT = max(0, self.plusT - dt)

    -- Glue mutes it: a tell still being counted in is dropped, and it rests.
    local muted = e.frozen > 0
    if muted and (self.state == "dropBuild" or self.state == "rollTip"
        or self.state == "shuffleTell" or self.state == "pairTell") then
        self:calm(e)
        self:rest(e, 0.4)
        game:say("MUTED")
    end

    -- The beat, which a muted speaker does not keep.
    local frac = self.clock % 1
    if not muted and self.state ~= "enter" then
        self.clock = self.clock + dt * pick(def.bpm, self.phase) / 60
        frac = self.clock % 1
        while floor(self.clock) > self.beat do
            self.beat = self.beat + 1
            self:onBeat(game, e)
        end
    end

    self.t = self.t - dt
    self[self.state](self, dt, game, e, body)

    self:flights(dt, game, e)
    self:pose(dt, e, body, frac, muted)
    body:update(dt)
end

-- What the body is doing this frame, off the beat and the state: the bounce,
-- the squash and the pump, the shake, and what the ring and the buttons show.
function SpeakerBoss:pose(dt, e, body, frac, muted)
    local state, lights = self.state, body.lights
    local planted = state == "rollTip" or state == "rolling" or state == "rollRise"
        or state == "enter"
    -- The bounce: up off the page through each beat and down on it, squashing
    -- as it lands. A speaker that is too loud walks itself across the table.
    local kick = (1 - frac) ^ 4
    if muted or planted then
        body.hop, body.squash, body.pump = 0, body.squash * 0.8, 0
    elseif state == "dropBuild" then
        -- Drawing breath: taller and thinner as the build goes on, trembling.
        local f = self.drop and self.drop.built or 0
        body.hop = 0
        body.squash = -0.9 * f
        body.pump = -1
    elseif state == "dropping" then
        body.hop = floor(sin(frac * math.pi) * 3 + 0.5)
        body.squash = kick * 1.6 - 0.2
        body.pump = kick * 2
    else
        body.hop = floor(sin(frac * math.pi) * self.def.hop + 0.5)
        body.squash = kick * 0.9
        body.pump = kick * 1.2
    end

    body.shake = (self.state == "dropBuild" and 0.3 + (self.drop and self.drop.built or 0))
        or (self.phase >= 3 and not muted and 0.3) or body.shake * 0.5
    if body.shake < 0.2 then body.shake = 0 end

    body.plus = self.plusT > 0 and floor(self.plusT * 10) % 2 == 0
    body.rune = state == "pairTell" and floor(self.t * 8) % 2 == 0

    -- The ring: off when muted, coming up on the entrance, and otherwise a
    -- meter of how loud it is -- a third, two, all of it -- chasing round, in
    -- the colour of whatever it is doing.
    lights.spin = lights.spin + dt * (state == "dropping" and 9 or 1.5)
    if muted then
        lights.colour = "off"
    elseif state == "enter" then
        lights.colour, lights.lit = "sky", floor((1 - max(0, self.t) / ENTER_TIME) * 12 + 0.5)
    elseif state == "dropBuild" then
        local f = self.drop and self.drop.built or 0
        lights.colour = floor(self.clock * (2 + f * 6)) % 2 == 0 and "red" or "off"
        lights.lit = 12
    elseif state == "dropping" or state == "shuffleTell" then
        lights.colour, lights.lit = "cycle", 12
    elseif state == "pairTell" then
        lights.colour = floor(self.t * 8) % 2 == 0 and "blue" or "sky"
        lights.lit = 12
    else
        lights.colour = self.phase >= 3 and "red" or "sky"
        lights.lit = self.phase * 4
    end
end

-- Every tell put back: whatever it was building, aiming or pairing.
function SpeakerBoss:calm(e)
    self.drop, self.aim, self.paired, self.handful = nil, nil, nil, nil
    e.chargePhase = nil
end

function SpeakerBoss:rest(e, t)
    self.state, self.t = "resting", t
    e.drive = { hold = true }
end

function SpeakerBoss:resting(dt, game, e, body)
    e.drive = { hold = true }
    -- Back on its foot, if a roll left it anything but.
    body:right(dt * 6)
    if self.t <= 0 then
        self.state = "idle"
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.6
    end
end

--- the beat ---------------------------------------------------------------------

-- On every beat: a puff round its foot, a note floating up now and then, a kick
-- on the bar, and whatever the move it is in wants doing on the beat.
function SpeakerBoss:onBeat(game, e)
    local down = self.beat % 4 == 0
    local body = e.speaker
    if self.state ~= "rolling" and self.state ~= "rollTip" and self.state ~= "rollRise" then
        self.puffs[#self.puffs + 1] = { x = e.x, y = e.y + body:footY(), t = 0,
            colour = self.state == "dropping" and Palette.slate or Palette.graphite }
    end
    if self.beat % 2 == 0 or self.state == "dropping" then self:float(e) end
    if down and self.state ~= "dropping" then Sfx.play("stamp", 0.55) end

    if self.state == "dropBuild" then
        self:buildBeat(game, e)
    elseif self.state == "dropping" then
        self:wave(game, e)
    elseif self.state == "pairTell" then
        self.paired.beats = self.paired.beats - 1
        if self.paired.beats <= 0 then self:pairGo(game, e) end
    elseif self.state == "idle" and self.phase >= self.def.thump.from and down then
        self:thump(game, e)
    end
end

-- A note off its top, drifting up and away: there is music coming out of it.
function SpeakerBoss:float(e)
    local tx, ty = e.speaker:top(e.x, e.y)
    self.floats[#self.floats + 1] = {
        x = tx + (love.math.random() - 0.5) * 8, y = ty - 2,
        dx = (love.math.random() - 0.5) * 24, t = 0,
        colour = love.math.random() < 0.5 and Palette.slate or Palette.ink,
    }
end

-- The last third's thump: on every downbeat while it walks, the bass round its
-- foot hurts. Told by the ring going red on the beat before, and by the beat
-- itself -- it is the one thing it does that you can count.
function SpeakerBoss:thump(game, e)
    local t = self.def.thump
    local p = game.player
    if util.len(p.x - e.x, p.y - e.y) < t.reach + p.radius * 0.5 then
        if p:hurt(scaled(e, t.damage)) then
            game.particles:burst(p.x, p.y, 6, Palette.red)
        end
    end
    self.blasts[#self.blasts + 1] = { x = e.x, y = e.y, r = t.reach, t = 0 }
    Camera.knock(1)
end

--- the entrance ---------------------------------------------------------------

-- Switched on: its lights come up one at a time with a rising chime, and on the
-- last of them the first beat lands.
function SpeakerBoss:enter(dt, game, e, body)
    e.drive = { hold = true }
    body:face(game.player.x - e.x, game.player.y - e.y, math.huge, dt)
    local f = 1 - max(0, self.t) / ENTER_TIME
    local lit = floor(f * 12 + 0.5)
    if lit > (self.chimed or 0) then
        self.chimed = lit
        Sfx.play("tick", 0.8 + lit * 0.06)
    end
    if self.t <= 0 then
        self.chimed = nil
        Sfx.play("transition2", 0.8)
        Sfx.play("stamp", 0.5)
        Camera.knock(3)
        body.squash = 1.5
        game.particles:burst(e.x, e.y - 12, 20, Palette.sky)
        for _ = 1, 3 do self:float(e) end
        self.puffs[#self.puffs + 1] = { x = e.x, y = e.y + body:footY(), t = 0,
            colour = Palette.slate, big = true }
        self.state, self.t = "idle", 0.8
    end
end

--- walking about --------------------------------------------------------------

-- Bouncing at you on the beat, turned so the + is towards you.
function SpeakerBoss:idle(dt, game, e, body)
    e.drive = nil
    body:right(dt * 6)
    body:face(game.player.x - e.x, game.player.y - e.y, 4, dt)
    if self.t <= 0 and e.frozen <= 0 then self:choose(game, e) end
end

-- The escort it could pair with: the nearest few of the crowd round you.
function SpeakerBoss:partners(game, e)
    local p, pr = game.player, self.def.pair
    local list = {}
    for _, o in ipairs(game.enemies) do
        if o ~= e and not o.def.boss and not o.ghost and o.hp > 0
            and util.len(o.x - p.x, o.y - p.y) < pr.range then
            list[#list + 1] = { o = o, d = util.len(o.x - p.x, o.y - p.y) }
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local out = {}
    for k = 1, min(#list, pick(pr.most, self.phase)) do out[k] = list[k].o end
    return out
end

-- The drop for anywhere; the roll for someone at a distance; the shuffle either
-- way; and from the second phase, pairing, when there is a crowd round you to
-- pair with. The last move is marked down.
function SpeakerBoss:choose(game, e)
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local pr = self.def.pair
    local w = {
        drop = 1.2,
        roll = d > 60 and 1.3 or 0.6,
        shuffle = 1.0,
        pair = 0,
    }
    if self.phase >= pr.from and #self:partners(game, e) >= pr.least then w.pair = 1.4 end
    if self.last then w[self.last] = w[self.last] * 0.3 end
    local sum = 0
    for _, v in pairs(w) do sum = sum + v end
    local r = love.math.random() * sum
    local move = "shuffle"
    for _, k in ipairs({ "drop", "roll", "shuffle", "pair" }) do
        r = r - w[k]
        if r <= 0 then move = k break end
    end
    self.last = move
    self[move .. "Start"](self, game, e, e.speaker)
end

--- the drop -------------------------------------------------------------------

-- A bar of build. The first ring's gap is picked now, off to one side of you,
-- and drawn on the floor for the whole of the build, so the first thing the
-- drop asks is that you go and stand in it.
function SpeakerBoss:dropStart(game, e, body)
    local dr = self.def.drop
    local p = game.player
    local at = math.atan2(p.y - e.y, p.x - e.x)
    local side = love.math.random() < 0.5 and -1 or 1
    self.drop = {
        x = e.x, y = e.y,
        gap = at + side * (0.7 + love.math.random() * 0.5),
        step = pick(dr.step, self.phase) * (love.math.random() < 0.5 and -1 or 1),
        width = pick(dr.gap, self.phase),
        build = dr.build, beats = 0, built = 0,
        left = pick(dr.waves, self.phase), sent = 0,
    }
    self.state, self.t = "dropBuild", 99
    e.drive = { hold = true }
    Sfx.play("tick", 1.0)
end

-- The rising ticks, doubling up on the last beat of the build.
function SpeakerBoss:buildBeat(game, e)
    local d = self.drop
    d.beats = d.beats + 1
    d.built = d.beats / d.build
    Sfx.play("tick", 1 + d.beats * 0.15)
    if d.beats >= d.build then
        self:dropGo(game, e)
    end
end

function SpeakerBoss:dropBuild(dt, game, e, body)
    e.drive = { hold = true }
    local d = self.drop
    -- And the ticks between the beats, quickening: eighths on the third beat
    -- and sixteenths on the last. A snare roll, as near as a tick gets to one.
    local frac = self.clock % 1
    local per = d.beats >= d.build - 1 and 4 or d.beats >= d.build - 2 and 2 or 1
    local sub = floor(frac * per)
    if per > 1 and sub > 0 and sub ~= d.sub then
        d.sub = sub
        Sfx.play("tick", 1 + d.beats * 0.15 + sub * 0.04)
    end
    if sub == 0 then d.sub = 0 end
    d.built = min(1, (d.beats + frac) / d.build)
end

-- DROP: the first ring, the crowd thrown back, and a ring a beat after it.
function SpeakerBoss:dropGo(game, e)
    local dr = self.def.drop
    self.state = "dropping"
    game:say("DROP!")
    Camera.knock(6)
    Sfx.play("transition2", 0.55)
    e.speaker.squash = 2
    game.particles:burst(e.x, e.y - 10, 30, Palette.red)
    game.particles:burst(e.x, e.y - 10, 20, Palette.sky)
    for _ = 1, 16 do
        game.particles:crumb(e.x, e.y + 8, nil, nil, e.radius, Palette.graphite)
    end
    -- The crowd round it thrown back by the first of it.
    game:eachWithin(e.x, e.y, dr.shoveReach, function(o)
        if o ~= e and not o.def.boss then
            local nx, ny = util.normalize(o.x - e.x, o.y - e.y)
            if nx == 0 and ny == 0 then nx = 1 end
            o:knockback(nx, ny, dr.shove)
        end
    end)
    self:wave(game, e, true)
end

-- One ring out of it, with the gap it was carrying, and the gap stepped on for
-- the next. At the last third the beat switches half way through.
function SpeakerBoss:wave(game, e, first)
    local d, dr = self.drop, self.def.drop
    if not d then return end
    if d.left <= 0 then
        self.drop = nil
        self:rest(e, pick(dr.rest, self.phase))
        return
    end
    local box = game.arena
    local far = 260
    if box then
        far = 0
        for _, c in ipairs({ { box.left, box.top }, { box:right(), box.top },
            { box.left, box:bottom() }, { box:right(), box:bottom() } }) do
            far = max(far, util.len(c[1] - e.x, c[2] - e.y))
        end
        far = far + 8
    end
    self.waves[#self.waves + 1] = {
        x = e.x, y = e.y, r = e.radius, far = far,
        gap = d.gap, width = d.width,
        speed = pick(dr.speed, self.phase),
        band = first and dr.band + 2 or dr.band,
        damage = scaled(e, dr.damage), pushed = {},
    }
    if not first then
        Sfx.play("stamp", 0.5)
        Camera.knock(2)
        e.speaker.squash = 1.6
    end
    d.left, d.sent = d.left - 1, d.sent + 1
    if self.phase >= 3 and d.sent == floor(pick(dr.waves, self.phase) / 2) then
        d.step = -d.step
    end
    d.gap = d.gap + d.step
    d.x, d.y = e.x, e.y
end

function SpeakerBoss:dropping(dt, game, e, body)
    e.drive = { hold = true }
end

--- the roll -------------------------------------------------------------------

-- Plant, aim, and go over. The aim is locked here and never looked at again:
-- the wad's rule, and what makes it a lane you can step out of.
function SpeakerBoss:rollStart(game, e, body)
    local p = game.player
    local dx, dy = util.normalize(p.x - e.x, p.y - e.y)
    if dx == 0 and dy == 0 then dx, dy = 1, 0 end
    self.aim = { dx = dx, dy = dy }
    local tip = pick(self.def.roll.tip, self.phase)
    self.state, self.t = "rollTip", tip
    self.tipRate = math.pi / 2 / (tip * 0.8)
    e.drive = { hold = true }
    Sfx.play("ruler", 0.6)
end

function SpeakerBoss:rollTip(dt, game, e, body)
    e.drive = { hold = true }
    e.chargePhase, e.phaseT = "wind", max(0, self.t)
    local aim = self.aim
    body:tip(aim.dx, aim.dy, self.tipRate * dt)
    if self.t <= 0 then
        self.dash = { dx = aim.dx, dy = aim.dy }
        self.aim = nil
        self.state, self.t = "rolling", self.def.roll.time
        self.bounces, self.stall, self.lastX = 0, 0, nil
        self.bowled = {}
        Camera.knock(2)
        Sfx.play("stamp", 0.7)
        for _ = 1, 8 do
            game.particles:crumb(e.x, e.y + 6, -aim.dx, -aim.dy, e.radius, Palette.graphite)
        end
    end
end

-- Down the lane and off the walls of the box -- the piggy bank's charge, read
-- off where the clamp left it -- turning the whole can at each bounce so it goes
-- on rolling across the way it goes, and bowling the crowd out of the lane.
function SpeakerBoss:rolling(dt, game, e, body)
    local r, dash = self.def.roll, self.dash
    e.chargePhase = "dash"

    -- How far it really went last frame, which is what turns it: a glued can
    -- does not spin on the spot.
    if self.lastX then
        local moved = util.len(e.x - self.lastX, e.y - self.lastY)
        body:roll(dash.dx, dash.dy, moved)
        if moved < pick(r.speed, self.phase) * dt * 0.25 and e.frozen <= 0 then
            self.stall = self.stall + 1
        else
            self.stall = 0
        end
    end
    self.lastX, self.lastY = e.x, e.y

    local box = game.arena
    local ox, oy = dash.dx, dash.dy
    local hit = false
    if box then
        local pad = e.radius + 0.5
        if dash.dx < 0 and e.x <= box.left + pad then dash.dx, hit = -dash.dx, true end
        if dash.dx > 0 and e.x >= box:right() - pad then dash.dx, hit = -dash.dx, true end
        if dash.dy < 0 and e.y <= box.top + pad then dash.dy, hit = -dash.dy, true end
        if dash.dy > 0 and e.y >= box:bottom() - pad then dash.dy, hit = -dash.dy, true end
    end
    if hit then
        self.bounces = self.bounces + 1
        body:spin(math.atan2(ox * dash.dy - oy * dash.dx, ox * dash.dx + oy * dash.dy))
        body.squash = 1.2
        Camera.knock(2)
        Sfx.play("ruler", 0.8)
        game.particles:burst(e.x, e.y, 10, Palette.sky)
    end

    -- The crowd in its way, thrown out of the lane to whichever side it is on.
    game:eachWithin(e.x, e.y, e.radius + 10, function(o)
        if o ~= e and not o.def.boss and not self.bowled[o] then
            self.bowled[o] = true
            local side = (o.x - e.x) * -dash.dy + (o.y - e.y) * dash.dx >= 0 and 1 or -1
            o:knockback(-dash.dy * side + dash.dx * 0.5, dash.dx * side + dash.dy * 0.5, r.fling)
            game.particles:burst(o.x, o.y, 3, Palette.graphite)
        end
    end)
    if love.math.random() < dt * 20 then
        game.particles:crumb(e.x - dash.dx * 8, e.y + 6 - dash.dy * 8, -dash.dx, -dash.dy, 6,
            Palette.graphite)
    end

    if (hit and self.bounces > pick(r.bounces, self.phase)) or self.stall >= 4 or self.t <= 0 then
        self.dash, self.lastX, self.bowled = nil, nil, nil
        e.chargePhase = nil
        self.state, self.t = "rollRise", r.rise
        e.drive = { hold = true }
        return
    end
    e.drive = { dash = true, dx = dash.dx, dy = dash.dy, speed = pick(r.speed, self.phase) }
end

-- Standing itself back up, slowly: the window.
function SpeakerBoss:rollRise(dt, game, e, body)
    e.drive = { hold = true }
    body:right(math.pi / 2 / self.def.roll.rise * dt)
    if self.t <= 0 then
        body:right(math.pi)
        body.squash = 1.2
        Sfx.play("stamp", 0.8)
        self:rest(e, pick(self.def.roll.rest, self.phase))
    end
end

--- the shuffle ----------------------------------------------------------------

function SpeakerBoss:shuffleStart(game, e, body)
    self.volleys = pick(self.def.shuffle.volleys, self.phase)
    self.state, self.t = "shuffleTell", pick(self.def.shuffle.tell, self.phase)
    self.handful = love.math.random() * TAU
    e.drive = { hold = true }
    Sfx.play("tick", 1.5)
end

-- Spinning, its lights chasing, the notes it is about to let go of going round
-- over its top.
function SpeakerBoss:shuffleTell(dt, game, e, body)
    e.drive = { hold = true }
    body:spin(dt * 9)
    self.handful = self.handful + dt * 4
    if self.t > 0 then return end
    local s = self.def.shuffle
    local tx, ty = body:top(e.x, e.y)
    local n = pick(s.count, self.phase)
    for k = 1, n do
        local a = self.handful + k / n * TAU
        self.notes[#self.notes + 1] = {
            x = tx, y = ty, dx = cos(a), dy = sin(a), speed = s.speed,
            life = s.life, damage = scaled(e, s.damage),
        }
    end
    Sfx.play("pin", 1.4)
    Camera.knock(1)
    body.squash = 1.2
    game.particles:burst(tx, ty, 8, Palette.red)
    self.volleys = self.volleys - 1
    if self.volleys > 0 then
        self.handful = self.handful + math.pi / n
        self.t = s.gap
    else
        self.handful = nil
        self:rest(e, pick(s.rest, self.phase))
    end
end

--- pairing --------------------------------------------------------------------

-- Its back to you, the rune lit, and the nearest of the crowd round you paired:
-- they go off together a couple of beats from now.
function SpeakerBoss:pairStart(game, e, body)
    local list = self:partners(game, e)
    local beats = pick(self.def.pair.beats, self.phase)
    self.paired = { list = list, beats = beats, gone = {} }
    self.state, self.t = "pairTell", 99
    e.drive = { hold = true }
    Sfx.play("accept", 1.3)
end

function SpeakerBoss:pairTell(dt, game, e, body)
    e.drive = { hold = true }
    -- Turned round to show you the rune.
    body:face(e.x - game.player.x, e.y - game.player.y, 8, dt)
    -- Anything paired that has gone is disconnected, with a fizz.
    local alive = {}
    for _, o in ipairs(game.enemies) do alive[o] = true end
    for _, o in ipairs(self.paired.list) do
        if not self.paired.gone[o] and (not alive[o] or o.hp <= 0) then
            self.paired.gone[o] = true
            game.particles:burst(o.x, o.y, 8, Palette.sky)
        end
    end
end

function SpeakerBoss:pairGo(game, e)
    local pr = self.def.pair
    local p = game.player
    local any = false
    for _, o in ipairs(self.paired.list) do
        if not self.paired.gone[o] and o.hp > 0 then
            any = true
            self.blasts[#self.blasts + 1] = { x = o.x, y = o.y, r = pr.blast, t = 0 }
            game.particles:burst(o.x, o.y, 8, Palette.red)
            if util.len(p.x - o.x, p.y - o.y) < pr.blast + p.radius * 0.5 then
                if p:hurt(scaled(e, pr.damage)) then
                    game.particles:burst(p.x, p.y, 6, Palette.red)
                end
            end
        end
    end
    if any then
        Camera.knock(3)
        Sfx.play("stamp", 1.1)
    end
    self.paired = nil
    self:rest(e, pick(pr.rest, self.phase))
end

--- what it lets go of -----------------------------------------------------------

-- The rings going out, the notes bouncing round the box, and the harmless
-- things the beat puts about. A ring hurts you once as it crosses you, unless
-- you are in its gap, and shoves the crowd it crosses outwards.
function SpeakerBoss:flights(dt, game, e)
    local p = game.player
    for i = #self.waves, 1, -1 do
        local w = self.waves[i]
        w.r = w.r + w.speed * dt
        local d = util.len(p.x - w.x, p.y - w.y)
        local quiet = apart(math.atan2(p.y - w.y, p.x - w.x), w.gap) < w.width / 2
        if not w.hit and not quiet and abs(d - w.r) < w.band + p.radius * 0.6 then
            w.hit = true
            if p:hurt(w.damage) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
        end
        game:eachWithin(w.x, w.y, w.r + 4, function(o)
            if o ~= e and not o.def.boss and not w.pushed[o] then
                local od = util.len(o.x - w.x, o.y - w.y)
                if od > w.r - 6 and apart(math.atan2(o.y - w.y, o.x - w.x), w.gap) >= w.width / 2 then
                    w.pushed[o] = true
                    local nx, ny = util.normalize(o.x - w.x, o.y - w.y)
                    if nx == 0 and ny == 0 then nx = 1 end
                    o:knockback(nx, ny, self.def.drop.push)
                end
            end
        end)
        if w.r > w.far then table.remove(self.waves, i) end
    end

    local box = game.arena
    local hit = self.def.shuffle.hit
    for i = #self.notes, 1, -1 do
        local n = self.notes[i]
        n.life = n.life - dt
        n.x, n.y = n.x + n.dx * n.speed * dt, n.y + n.dy * n.speed * dt
        if box then
            if (n.x < box.left + 3 and n.dx < 0) or (n.x > box:right() - 3 and n.dx > 0) then
                n.dx = -n.dx
                game.particles:burst(n.x, n.y, 2, Palette.red)
            end
            if (n.y < box.top + 3 and n.dy < 0) or (n.y > box:bottom() - 3 and n.dy > 0) then
                n.dy = -n.dy
                game.particles:burst(n.x, n.y, 2, Palette.red)
            end
        end
        local done = n.life <= 0
        if not done and util.len(p.x - n.x, p.y - n.y) < p.radius + hit * e.reach then
            if p:hurt(n.damage) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
            done = true
        end
        if done then table.remove(self.notes, i) end
    end

    for i = #self.puffs, 1, -1 do
        local f = self.puffs[i]
        f.t = f.t + dt
        if f.t >= PUFF_TIME then table.remove(self.puffs, i) end
    end
    for i = #self.floats, 1, -1 do
        local f = self.floats[i]
        f.t = f.t + dt
        f.x, f.y = f.x + f.dx * dt, f.y - 22 * dt
        if f.t >= FLOAT_TIME then table.remove(self.floats, i) end
    end
    for i = #self.blasts, 1, -1 do
        local b = self.blasts[i]
        b.t = b.t + dt
        if b.t >= BLAST_TIME then table.remove(self.blasts, i) end
    end
end

--- going down -----------------------------------------------------------------

-- Down, everything it was playing stops: the rings and the notes go, and the
-- pairings drop. Called by Game:killEnemy.
function SpeakerBoss:dropParts(game)
    local e = self.e
    for _, n in ipairs(self.notes) do game.particles:burst(n.x, n.y, 2, Palette.red) end
    self.waves, self.notes, self.blasts, self.paired, self.drop = {}, {}, {}, nil, nil
    if not e or not e.speaker then return end
    e.speaker.lights.colour = "off"
    e.speaker.rune, e.speaker.plus = false, false
    game.particles:burst(e.x, e.y - 12, 30, Palette.sky)
end

--- drawing --------------------------------------------------------------------

local function dashes(x0, y0, dx, dy, len, phase, on)
    on = on or 3
    for i = 0, floor(len) do
        if floor((i - phase) / on) % 2 == 0 then
            love.graphics.rectangle("fill", floor(x0 + dx * i), floor(y0 + dy * i), 1, 1)
        end
    end
end

-- A ring of radius r round (x, y), a pixel at a time, leaving out the arc
-- `width` wide centred on `gap` (none when gap is nil). Dotted when `dot` is.
local function arc(x, y, r, gap, width, dot)
    if r < 1 then return end
    local n = floor(TAU * r * 1.2) + 8
    local half = width and width / 2 or 0
    local lx, ly
    for k = 0, n - 1 do
        local a = k / n * TAU
        if not gap or apart(a, gap) >= half then
            local px, py = floor(x + cos(a) * r), floor(y + sin(a) * r)
            if px ~= lx or py ~= ly then
                if not dot or (px + py) % 3 == 0 then
                    love.graphics.rectangle("fill", px, py, 1, 1)
                end
                lx, ly = px, py
            end
        end
    end
end

-- A ring `band` thick, outer edge at radius r round (x, y), leaving out the arc
-- `width` wide centred on `gap`. Drawn a row of the screen at a time as spans
-- between its outer and inner circles rather than a pixel at a time round it:
-- a drop has up to a dozen rings out at once, most of them wider than the box,
-- and one rectangle a span is a few hundred a ring where a pixel a step was
-- thousands. A span is checked against the gap at its middle when it is short,
-- which is nearly all of them; the few wide ones along the top and bottom of the
-- ring, where it runs flat, are walked a pixel at a time.
local function ring(x, y, r, band, gap, width)
    if r < 1 then return end
    local half = width / 2
    local inner = r - band
    local function span(a, b, dy)
        if b < a then return end
        if b - a <= 3 then
            if apart(math.atan2(dy, (a + b) / 2), gap) >= half then
                love.graphics.rectangle("fill", x + a, y + dy, b - a + 1, 1)
            end
            return
        end
        local from
        for px = a, b + 1 do
            local out = px <= b and apart(math.atan2(dy, px), gap) >= half
            if out and not from then from = px end
            if not out and from then
                love.graphics.rectangle("fill", x + from, y + dy, px - from, 1)
                from = nil
            end
        end
    end
    local top = floor(r)
    for dy = -top, top do
        local xo = floor(math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
        if abs(dy) < inner then
            local xi = floor(math.sqrt(inner * inner - dy * dy) + 0.5)
            span(-xo, -xi, dy)
            span(xi, xo, dy)
        else
            span(-xo, xo, dy)
        end
    end
end

-- On the floor: the puffs of the beat, the gap the next ring of a drop will
-- carry (in your blue: it is the safe place), the roll's lane, and the pairings.
function SpeakerBoss:drawGround(time)
    local e = self.e
    if not e then return end

    for _, f in ipairs(self.puffs) do
        local k = f.t / PUFF_TIME
        love.graphics.setColor(k < 0.5 and f.colour or Palette.graphite)
        pixelart.circleOutline(floor(f.x), floor(f.y),
            floor(6 + k * (f.big and 40 or 14)))
    end

    local d = self.drop
    if d and (self.state == "dropBuild" or self.state == "dropping") then
        love.graphics.setColor(Palette.blue)
        for _, side in ipairs({ -1, 1 }) do
            local a = d.gap + side * d.width / 2
            dashes(d.x + cos(a) * 18, d.y + sin(a) * 18, cos(a), sin(a), 70, time * 40, 3)
        end
        love.graphics.setColor(Palette.sky)
        arc(d.x, d.y, 60, d.gap + math.pi, TAU - d.width, true)
        -- Through the build, the red that is going to go out everywhere but there.
        if self.state == "dropBuild" then
            love.graphics.setColor(floor(time * 8) % 2 == 0 and Palette.red or Palette.blush)
            arc(d.x, d.y, 18 + d.built * 10, d.gap, d.width, true)
        end
    end

    local aim = self.aim
    if aim then
        love.graphics.setColor(Palette.red)
        local len = self.def.roll.lane
        local half = e.radius
        for _, side in ipairs({ -1, 1 }) do
            local x0 = e.x + aim.dx * (e.radius + 2) - aim.dy * half * side
            local y0 = e.y + aim.dy * (e.radius + 2) + aim.dx * half * side
            dashes(x0, y0, aim.dx, aim.dy, len, time * 30, 4)
        end
        local tx = e.x + aim.dx * (e.radius + 2 + len)
        local ty = e.y + aim.dy * (e.radius + 2 + len)
        local a = math.atan2(aim.dy, aim.dx)
        for _, side in ipairs({ -1, 1 }) do
            local b = a + math.pi * 0.8 * side
            pixelart.line(floor(tx), floor(ty), floor(tx + cos(b) * 7), floor(ty + sin(b) * 7))
        end
    end

    local pr = self.paired
    if pr then
        local tx, ty = e.speaker:top(e.x, e.y)
        local on = floor(time * 10) % 2 == 0
        for _, o in ipairs(pr.list) do
            if not pr.gone[o] then
                local dx, dy, dist = util.normalize(o.x - tx, o.y - ty)
                love.graphics.setColor(Palette.slate)
                dashes(tx, ty, dx, dy, dist, -time * 40, 2)
                love.graphics.setColor(on and Palette.red or Palette.blush)
                arc(o.x, o.y, self.def.pair.blast, nil, nil, true)
            end
        end
    end
end

-- A note on the page, the way the metronome's are drawn.
local function note(x, y)
    love.graphics.setColor(1, 1, 1)
    Sprites.note:draw(x, y)
end

-- Over the crowd: the rings, the notes, the blasts, and the music coming out.
function SpeakerBoss:drawAir(time, e)
    for _, w in ipairs(self.waves) do
        local x, y = floor(w.x), floor(w.y)
        love.graphics.setColor(Palette.red)
        ring(x, y, w.r, w.band, w.gap, w.width)
        love.graphics.setColor(Palette.blush)
        ring(x, y, w.r - w.band - 2, 1, w.gap, w.width)
    end

    for _, n in ipairs(self.notes) do
        -- Blinking out for its last moment.
        if n.life > 0.8 or floor(n.life * 12) % 2 == 0 then note(n.x, n.y) end
    end

    for _, b in ipairs(self.blasts) do
        local k = b.t / BLAST_TIME
        love.graphics.setColor(k < 0.6 and Palette.red or Palette.blush)
        pixelart.circleOutline(floor(b.x), floor(b.y), floor(4 + k * (b.r - 4)))
    end

    -- The shuffle's handful going round over its top while it spins.
    if self.handful and e and e.speaker then
        local tx, ty = e.speaker:top(e.x, e.y)
        local n = pick(self.def.shuffle.count, self.phase)
        if floor(time * 12) % 2 == 0 then
            for k = 1, n do
                local a = self.handful + k / n * TAU
                note(tx + cos(a) * 16, ty - 6 + sin(a) * 6)
            end
        end
    end

    -- The music coming out of it: little notes floating up and away.
    for _, f in ipairs(self.floats) do
        local k = f.t / FLOAT_TIME
        if k < 0.75 or floor(f.t * 20) % 2 == 0 then
            local x, y = floor(f.x), floor(f.y)
            love.graphics.setColor(k < 0.5 and f.colour or Palette.graphite)
            love.graphics.rectangle("fill", x, y + 2, 2, 2)
            love.graphics.rectangle("fill", x + 1, y - 2, 1, 4)
            love.graphics.rectangle("fill", x + 2, y - 2, 1, 1)
        end
    end
end

return SpeakerBoss
