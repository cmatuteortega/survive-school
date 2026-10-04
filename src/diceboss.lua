-- The MATHS boss's mind: a die, and the fight in the book about *number*.
--
-- The eye is a fight about the ground, the whistle about the air and the
-- metronome about time. This one is about reading a number. Everything it does
-- is decided by a roll, and the roll is not hidden: the die is thrown across
-- the box, tumbles, comes to rest -- and the face on top says what is coming,
-- and how much of it, before any of it comes. A boss that rolled for its moves
-- in secret would be the one unfair thing in the book; this one rolls in front
-- of you and then gives you a count-in to read the answer. Luck picks the move.
-- You always see the move before it lands.
--
-- **The throw** is how it gets about: it does not walk. It stands, shudders red
-- with the way it is going to go drawn on the floor in front of it, and then
-- throws itself down that line, tumbling end over end, bouncing off the walls
-- of the box and slowing to a stop -- which is a dash you step off, the wad's
-- bargain at a boss's size. Where it stops is where it rolls.
--
-- **The d6** (the first third) rolls a face, and the face is stamped on the
-- floor: three by three squares of the page round where you are standing, and
-- the squares where that face has its pips go off. Read the die, find the blank
-- squares, stand on one. Then it spits that many pips at you.
--
-- **It unfolds** at two thirds: the cube opens out flat into its net, six faces
-- in a cross laid square on the page round where it stood, and the net is hot
-- -- then it folds itself back up into a d10.
--
-- **The d10** (the middle third) rolls odds and evens. The whole box is a
-- checkerboard of the page's squares, and the half of it whose parity matches
-- the roll goes off: an odd roll, the odd squares. Then a ring of that many
-- pips, out from the die.
--
-- **It is recast** at one third: it leaps off the page, its shadow comes down
-- on where you are standing, and it lands there as a d20 -- get out from under
-- it.
--
-- **The d20** (the last third) rolls spokes: that many lines out from the die
-- across the floor, swinging a little round when they go off. A low roll is
-- wide gaps anywhere; a high one is gaps you only fit through far out. Two
-- rolls are special, as on every d20. **A natural 20 is a critical**: the
-- spokes, then both halves of the checkerboard one after the other, so you
-- cross from one to the other. **A natural 1 is a fumble**: it falls over,
-- seeing stars, and takes half again from everything for a few seconds -- the
-- roll you cheer.
--
-- **Glue loads the die.** A glued die drops whatever it was counting in, and
-- one glued while it is still rolling lands on 1 -- which on the d20 is the
-- fumble. It is the one tool-shaped answer this fight has, as it is the eye's
-- and the metronome's, and a loaded die is the one a die deserves.
--
-- The body is src/dice.lua, painted every frame; this file only throws it,
-- tells it when to settle and what to become, and reads it.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local Font = require("src.font")
local Dice = require("src.dice")
local pixelart = require("src.pixelart")
local util = require("src.util")

local DiceBoss = {}
DiceBoss.__index = DiceBoss

local TAU = math.pi * 2
local floor = math.floor

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new).
local function scaled(e, damage) return damage * e.damage / e.def.damage end

function DiceBoss.new(def)
    return setmetatable({
        def = def.dice,
        phase = 1,
        -- It walks on already winding up its first throw: the spawner put it
        -- down somewhere, and a die is thrown, not walked on.
        state = "wind", t = def.dice.throw.wind[1] + 0.4,
        aim = nil,
        roll = nil,        -- the number on top, once it has landed
        queue = {}, strike = nil,
        loaded = false,    -- glued while rolling: this roll is a 1
        sub = nil,
        e = nil,
    }, DiceBoss)
end

function DiceBoss:busy()
    return self.state ~= "rest"
end

-- What a hit on it is worth: half again while it lies there fumbled
-- (Enemy:hurt asks).
function DiceBoss:soften()
    return self.state == "fumble" and self.def.fumble.soften or 1
end

--- the loop -------------------------------------------------------------------

function DiceBoss:update(dt, game, e)
    self.e, self.box = e, game.arena
    if dt <= 0 then return end
    local body = e.dice
    if self.shockT then self.shockT = math.max(0, self.shockT - dt) end

    -- The phase, at the eye's thirds: each one is a bigger die, and getting
    -- there is a move of its own. Whatever it was in the middle of is dropped.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self:clear(e)
        self.phase = phase
        game.particles:burst(e.x, e.y, phase >= 3 and 24 or 14, Palette.red)
        -- Two thirds gone in one go skips the net: the cube is recast straight
        -- into a d20, which is the move that ends on one.
        if phase == 2 then
            self.state, self.sub, self.t = "unfold", "shake", self.def.net.shake
        else
            self.state, self.sub, self.t = "recast", "up", self.def.recast.up
        end
    end

    -- Stuck to the page. The two changes of shape go on regardless -- the die
    -- is off the page for most of them -- but anything else stops, and a tell
    -- it was counting in is dropped. Glued while it is *rolling*, it is loaded
    -- too: it lands on 1. Only while rolling, so that the loaded die is a shot
    -- you make at a moving thing -- glue that loaded it whenever it landed
    -- would let a glue build keep a d20 fumbling for the whole last third.
    if e.frozen > 0 and self.state ~= "unfold" and self.state ~= "recast" then
        if not self.loaded and (self.state == "tumble" or self.state == "settle") then
            self.loaded = true
            game.particles:burst(e.x, e.y, 6, Palette.sky)
        end
        if self.state == "show" and self.strike and self.strike.stage == "tell" then
            self:clear(e)
            self.state, self.t = "rest", pick(self.def.rest, self.phase)
        end
        e.blowT, e.hop = 0, 0
        e.drive = { hold = true }
        return
    end

    e.drive = { hold = true }
    self.t = self.t - dt
    self[self.state](self, dt, game, e, body)
end

-- Done with whatever it was doing: off the page with it.
function DiceBoss:clear(e)
    self.queue, self.strike, self.aim = {}, nil, nil
    e.blowT, e.hop, e.ghost = 0, 0, false
    if e.dice then e.dice.hidden = false end
end

-- Standing, between one throw and the next: the window the last move paid for.
function DiceBoss:rest(dt, game, e)
    if self.t <= 0 then
        self.state, self.t, self.aim = "wind", pick(self.def.throw.wind, self.phase), nil
    end
end

--- the throw ------------------------------------------------------------------

-- How far a line along `a` from (x, y) goes before the box stops it.
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

-- The wind-up. The line is locked at the top of it and drawn on the floor, and
-- the die shudders and blinks red the way the whistle does before its blast
-- (`blowT`, read by Enemy:footing and Enemy:outlineColour) -- the one way this
-- game says something big is coming.
function DiceBoss:wind(dt, game, e)
    local th = self.def.throw
    if not self.aim then
        local p = game.player
        local a = math.atan2(p.y - e.y, p.x - e.x)
        self.aim = a + (love.math.random() * 2 - 1) * th.spread
    end
    e.blowT = math.max(0, self.t)
    if self.t <= 0 then
        e.blowT = 0
        self.dx, self.dy = math.cos(self.aim), math.sin(self.aim)
        self.v0 = pick(th.speed, self.phase)
        self.T = pick(th.time, self.phase)
        self.tt, self.hopsDone = 0, 0
        -- And a flick of the wrist: a spin about the upright, either way, that
        -- runs down with the throw. Without it the face it lands on would be a
        -- sum of the line and the distance -- the same throw, the same roll.
        self.twist = (love.math.random() * 2 - 1) * th.twist
        self.state = "tumble"
        Sfx.play("tick", 0.8)
    end
end

-- Down the line, slowing to a stop: a linear run-down, so the distance is
-- half of speed times time and the far end of the arrow is where it stops.
-- The walls of the box send it back the way a wall sends a die back, and a few
-- hops on the way -- each smaller than the last -- are the clatter.
function DiceBoss:tumble(dt, game, e, body)
    local th = self.def.throw
    self.tt = self.tt + dt
    local f = math.min(1, self.tt / self.T)
    local sp = self.v0 * (1 - f)
    local vx, vy = self.dx * sp, self.dy * sp
    local x, y = e.x + vx * dt, e.y + vy * dt
    local box = game.arena
    if box then
        local r = e.radius
        local bounced = false
        if (x < box.left + r and self.dx < 0) or (x > box:right() - r and self.dx > 0) then
            self.dx, bounced = -self.dx, true
        end
        if (y < box.top + r and self.dy < 0) or (y > box:bottom() - r and self.dy > 0) then
            self.dy, bounced = -self.dy, true
        end
        if bounced then
            Sfx.play("tick", 0.9 + love.math.random() * 0.3)
            Camera.knock(1)
            game.particles:burst(x, y, 4, Palette.graphite)
        end
    end
    e.x, e.y = x, y
    e.headX, e.headY = self.dx, self.dy
    body:roll(vx, vy, dt)
    body:turn(0, 0, 1, self.twist * (1 - f) * dt)

    local hops = floor(f * th.hops)
    if hops > self.hopsDone and f < 1 then
        self.hopsDone = hops
        Sfx.play("tick", 1.1 + love.math.random() * 0.3)
        game.particles:burst(e.x, e.y + e.radius, 3, Palette.graphite)
    end
    local lift = th.high * (1 - f) * math.abs(math.sin(math.pi * th.hops * f))
    e.hop = floor(lift + 0.5)

    if f >= 1 then
        e.hop = 0
        self.state = "settle"
    end
end

-- Tipping the rest of the way onto a face, or onto the 1 if it was glued.
function DiceBoss:settle(dt, game, e, body)
    local face = body:settle(dt, self.def.throw.settle, self.loaded and 1 or nil)
    if face then
        self.loaded = false
        self:land(game, e, face)
    end
end

--- the roll -------------------------------------------------------------------

-- Landed, and what is on top is what happens. The moves are queued as
-- strikes, each with its own count-in, and played one after another.
function DiceBoss:land(game, e, face)
    local n = face.label
    local def = self.def
    self.roll = n
    Sfx.play("pin")
    Camera.knock(1)
    game.particles:burst(e.x, e.y + e.radius, 6, Palette.graphite)

    local shape = e.dice.shape
    self.queue, self.volley = {}, nil
    if shape == "d6" then
        self.queue[1] = { kind = "stamp", n = n, face = face }
        self.volley = { kind = "fan", n = n }
    elseif shape == "d10" then
        self.queue[1] = { kind = "checker", parity = n % 2 }
        self.volley = { kind = "ring", n = n }
    elseif n == 1 then
        self.state, self.t = "fumble", def.fumble.time
        game:say("FUMBLE!")
        Camera.knock(2)
        return
    elseif n == 20 then
        local tell = def.crit.tell
        self.queue[1] = { kind = "spokes", n = 20, tell = tell[1] }
        self.queue[2] = { kind = "checker", parity = 1, tell = tell[2] }
        self.queue[3] = { kind = "checker", parity = 0, tell = tell[3] }
        game:say("CRITICAL!")
        Camera.knock(3)
    else
        self.queue[1] = { kind = "spokes", n = n }
    end
    self.state = "show"
    self:nextStrike(game, e)
end

-- The next strike off the queue: built now, so where it falls is locked at the
-- top of its count-in, and counted in.
function DiceBoss:nextStrike(game, e)
    local s = table.remove(self.queue, 1)
    self.strike = s
    if not s then return end
    local def = self.def[s.kind]
    s.stage, s.t = "tell", s.tell or def.tell
    s.hot = def.hot
    self["build_" .. s.kind](self, game, e, s, def)
end

-- Counting in, then hot, then the next strike or, at the end of the queue, the
-- volley and the rest.
function DiceBoss:show(dt, game, e)
    local s = self.strike
    if not s then
        self:fire(game, e)
        self.state, self.t = "rest", pick(self.def.rest, self.phase)
        return
    end
    s.t = s.t - dt
    if s.stage == "tell" then
        if s.t <= 0 then
            s.stage, s.t, s.age = "hot", s.hot, 0
            Camera.knock(2)
            Sfx.play("pin", 0.8)
        end
    else
        s.age = s.age + dt
        self:hit(game, e, s)
        if s.t <= 0 then self:nextStrike(game, e) end
    end
end

-- Lying on its side, seeing stars: the fumble. Nothing it does; everything
-- you do counts for half again (DiceBoss:soften).
function DiceBoss:fumble(dt, game, e)
    if self.t <= 0 then
        self.state, self.t = "rest", 0.4
    end
end

--- the strikes ----------------------------------------------------------------

-- Cells of the page, `size` across, snapped to the page's own squares so the
-- floor that goes off is squares you can see -- squared paper is ruled every
-- ten pixels, and every cell here is a whole number of its squares.
local function snap(v, size) return floor(v / size) * size end

-- The d6's face, stamped round you: a three by three of cells with the face's
-- pips on it. Laid the way the pips lie on the top of the die, so a 2 running
-- corner to corner across the die runs that way across the floor too.
function DiceBoss:build_stamp(game, e, s, def)
    local p = game.player
    local c = def.cell
    local cx, cy = snap(p.x, c), snap(p.y, c)
    -- Which way the face's first axis runs on the floor.
    local face = s.face
    local ax = e.dice.ax
    local ay = e.dice.ay
    local az = e.dice.az
    local u = face.u
    local wx = ax[1] * u[1] + ay[1] * u[2] + az[1] * u[3]
    local wy = ax[2] * u[1] + ay[2] * u[2] + az[2] * u[3]
    local swap = math.abs(wy) > math.abs(wx)
    s.x0, s.y0, s.cell = cx - c, cy - c, c
    s.cells = {}
    for _, pip in ipairs(Dice.PIPS[s.n]) do
        local i, j = pip[1], pip[2]
        if swap then i, j = j, i end
        s.cells[#s.cells + 1] = { x = cx + i * c, y = cy + j * c }
    end
end

-- Odds and evens: every cell of the box whose column and row add up to the
-- roll's parity. Nothing to build but the parity -- the box is the board.
function DiceBoss:build_checker(game, e, s, def)
    s.cell = def.cell
end

-- The spokes: `n` lines out from where it stands, at a turn of the board you
-- cannot learn, swinging `turn` of a gap round while they are hot.
function DiceBoss:build_spokes(game, e, s, def)
    s.x, s.y = e.x, e.y
    s.a0 = love.math.random() * TAU
    s.dir = love.math.random() < 0.5 and -1 or 1
    s.swing = def.turn * TAU / s.n
end

-- Where spoke `k` points, `f` of the way through its swing.
local function spokeAngle(s, k, f)
    return s.a0 + s.dir * s.swing * f + (k - 1) * TAU / s.n
end

-- The net: the cube opened out flat, a cross of six faces round the cell it
-- stood on, each with its own pips.
function DiceBoss:build_net(game, e, s, def)
    local c = def.cell
    local cx, cy = snap(e.x, c) + c / 2, snap(e.y, c) + c / 2
    s.cx, s.cy, s.cell = cx, cy, c
    s.cells = {}
    local layout = { { 0, -1, 2 }, { -1, 0, 4 }, { 0, 0, 1 }, { 1, 0, 3 }, { 0, 1, 5 }, { 0, 2, 6 } }
    for _, l in ipairs(layout) do
        s.cells[#s.cells + 1] = { x = cx - c / 2 + l[1] * c, y = cy - c / 2 + l[2] * c, n = l[3] }
    end
end

-- Whether (x, y) is in a cell of the board of this parity, inside the box.
local function onChecker(game, s, x, y)
    if game.arena and not game.arena:contains(x, y) then return false end
    local i, j = floor(x / s.cell), floor(y / s.cell)
    return (i + j) % 2 == s.parity
end

local function inCells(s, x, y)
    for _, c in ipairs(s.cells) do
        if x >= c.x and x < c.x + s.cell and y >= c.y and y < c.y + s.cell then return true end
    end
    return false
end

-- A strike going off: does it have you. Your middle in a hot cell is in it --
-- a cell is a place you can see, and your middle is where you are standing.
function DiceBoss:hit(game, e, s)
    local p = game.player
    local def = self.def[s.kind]
    local caught = false
    if s.kind == "stamp" or s.kind == "net" then
        caught = inCells(s, p.x, p.y)
    elseif s.kind == "checker" then
        caught = onChecker(game, s, p.x, p.y)
    elseif s.kind == "spokes" then
        local f = math.min(1, s.age / s.hot)
        for k = 1, s.n do
            local a = spokeAngle(s, k, f)
            local len = reach(game, s.x, s.y, a, def.length)
            local x1, y1 = s.x + math.cos(a) * len, s.y + math.sin(a) * len
            if util.distToSegment(p.x, p.y, s.x, s.y, x1, y1) < p.radius + def.width / 2 then
                caught = true
                break
            end
        end
    end
    if caught and p:hurt(scaled(e, def.damage)) then
        game.particles:burst(p.x, p.y, 6, Palette.red)
    end
end

-- The pips it spits after a roll: a fan of that many at you off the d6, a
-- ring of that many out from the d10. The number on the die is how many.
function DiceBoss:fire(game, e)
    local v = self.volley
    self.volley = nil
    if not v then return end
    local pd = self.def.pips
    local p = game.player
    local at = math.atan2(p.y - e.y, p.x - e.x)
    for k = 0, v.n - 1 do
        local a
        if v.kind == "fan" then
            a = at + (k - (v.n - 1) / 2) * pd.arc
        else
            a = at + k * TAU / v.n
        end
        game.shots[#game.shots + 1] = {
            x = e.x, y = e.y, dx = math.cos(a), dy = math.sin(a), speed = pd.speed,
            damage = scaled(e, pd.damage), life = pd.life, sprite = pd.sprite,
            radius = pd.hit * e.reach, grow = e.grow,
        }
    end
    Sfx.play("tick", 1.4)
end

--- changing shape -------------------------------------------------------------

-- Two thirds: the cube shudders, opens out flat into its net, the net goes
-- off, and it folds back up as a d10. Off the page while it is a net -- there
-- is no die there to hit, only floor to keep off.
function DiceBoss:unfold(dt, game, e, body)
    local net = self.def.net
    e.hitCooldown = math.max(e.hitCooldown, 0.1)
    -- The net keeps this clock rather than one of its own, so its tell blinks
    -- red on the same last third of a second every other tell does.
    if self.strike then self.strike.t = self.t end
    if self.sub == "shake" then
        e.blowT = math.max(0, self.t)
        if self.t <= 0 then
            e.blowT = 0
            body.hidden, e.ghost = true, true
            local s = { kind = "net" }
            self:build_net(game, e, s, net)
            s.stage, s.t = "tell", net.tell
            self.strike = s
            self.sub, self.t = "open", net.tell
            Sfx.play("pin", 0.7)
            game.particles:burst(e.x, e.y, 12, Palette.red)
        end
    elseif self.sub == "open" then
        if self.t <= 0 then
            self.strike.stage = "hot"
            self.sub, self.t = "hot", net.hot
            Camera.knock(3)
            Sfx.play("pin", 0.6)
        end
    elseif self.sub == "hot" then
        self:hit(game, e, self.strike)
        if self.t <= 0 then
            self.strike.stage = "fold"
            self.sub, self.t = "fold", net.fold
        end
    elseif self.sub == "fold" then
        self.strike.fold = 1 - math.max(0, self.t) / net.fold
        if self.t <= 0 then
            self.strike = nil
            body:become("d10")
            body.hidden, e.ghost = false, false
            game.particles:burst(e.x, e.y, 18, Palette.red)
            Camera.knock(2)
            game:say("MORE SIDES!")
            self.state, self.t = "rest", 0.6
        end
    end
end

-- One third: it leaps off the top of the page, its shadow comes down on where
-- you were standing, and it lands there as a d20 with a ring that hurts.
function DiceBoss:recast(dt, game, e, body)
    local rc = self.def.recast
    e.hitCooldown = math.max(e.hitCooldown, 0.1)
    e.ghost = true
    if self.sub == "up" then
        local f = 1 - math.max(0, self.t) / rc.up
        e.hop = floor(rc.high * f * f)
        body:turn(1, 0.3, 0, dt * 14)
        if self.t <= 0 then
            local p = game.player
            local x, y = p.x, p.y
            if game.arena then x, y = game.arena:clamp(x, y, e.radius + 4) end
            self.mark = { x = x, y = y }
            body.hidden = true
            self.sub, self.t = "aim", rc.aim
        end
    elseif self.sub == "aim" then
        if self.t <= 0 then
            e.x, e.y = self.mark.x, self.mark.y
            body:become("d20")
            body.hidden = false
            self.sub, self.t = "down", rc.down
        end
    elseif self.sub == "down" then
        local f = math.max(0, self.t) / rc.down
        e.hop = floor(rc.high * f * f)
        body:turn(0.2, 1, 0, dt * 14)
        if self.t <= 0 then
            e.hop, e.ghost = 0, false
            self.mark = nil
            local p = game.player
            if util.len(p.x - e.x, p.y - e.y) < rc.shock and p:hurt(scaled(e, rc.damage)) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
            self.shockT = 0.3
            Camera.knock(4)
            Sfx.play("pin", 0.5)
            game.particles:burst(e.x, e.y, 24, Palette.red)
            for _ = 1, 10 do game.particles:crumb(e.x, e.y + e.radius, nil, nil, e.radius, Palette.graphite) end
            game:say("MORE SIDES!")
            -- Lands on whatever face it lands on, and that is a roll.
            self.state = "settle"
        end
    end
end

--- drawing --------------------------------------------------------------------

-- A cell's outline, `inset` in from its edge.
local function box(x, y, w, h)
    x, y = floor(x), floor(y)
    love.graphics.rectangle("fill", x, y, w, 1)
    love.graphics.rectangle("fill", x, y + h - 1, w, 1)
    love.graphics.rectangle("fill", x, y, 1, h)
    love.graphics.rectangle("fill", x + w - 1, y, 1, h)
end

-- Dashes along a line, marching outwards: the tells.
local function dashes(x, y, a, len, shift, on)
    on = on or 3
    local dx, dy = math.cos(a), math.sin(a)
    for d = 0, len, 1 do
        if floor((d - shift) / on) % 2 == 0 then
            love.graphics.rectangle("fill", floor(x + dx * d), floor(y + dy * d), 1, 1)
        end
    end
end

-- A ring dotted, for where something will come down.
local function dottedRing(cx, cy, r, phase)
    local n = math.max(12, floor(r * 0.9))
    for i = 0, n - 1 do
        if (i + phase) % 2 == 0 then
            local a = i / n * TAU
            love.graphics.rectangle("fill", floor(cx + math.cos(a) * r),
                floor(cy + math.sin(a) * r), 1, 1)
        end
    end
end

-- The colour of a tell: slate, blinking red over its last third of a second.
local function tellColour(s, time)
    if s.t < 0.35 and floor(time * 10) % 2 == 0 then return Palette.red end
    return Palette.slate
end

-- A face of the die drawn on the floor, `c` across: its pips, and either an
-- outline (the tell) or filled red (going off).
local function floorFace(x, y, c, n, hot, colour)
    if hot then
        love.graphics.setColor(Palette.red)
        love.graphics.rectangle("fill", floor(x), floor(y), c, c)
        love.graphics.setColor(Palette.paper)
    else
        love.graphics.setColor(colour)
        box(x + 2, y + 2, c - 4, c - 4)
    end
    if n then
        local r = math.max(2, floor(c / 9))
        for _, p in ipairs(Dice.PIPS[n]) do
            pixelart.circleFill(floor(x + c / 2 + p[1] * c / 4), floor(y + c / 2 + p[2] * c / 4), r)
        end
    end
end

-- On the floor: the throw's line, every strike's cells and spokes, and the
-- shadow of a die coming down.
function DiceBoss:drawGround(time)
    local e = self.e
    if not e then return end

    if self.state == "wind" and self.aim then
        local th = self.def.throw
        local len = pick(th.speed, self.phase) * pick(th.time, self.phase) / 2
        love.graphics.setColor(floor(time * 10) % 2 == 0 and Palette.red or Palette.slate)
        dashes(e.x, e.y, self.aim, len, time * 30)
    end

    if self.mark then
        love.graphics.setColor(floor(time * 8) % 2 == 0 and Palette.red or Palette.slate)
        dottedRing(self.mark.x, self.mark.y, self.def.recast.shock, floor(time * 6))
        love.graphics.setColor(Palette.graphite)
        local f = self.sub == "aim" and 1 - math.max(0, self.t) / self.def.recast.aim or 1
        pixelart.circleFill(floor(self.mark.x), floor(self.mark.y + e.radius), floor(4 + f * 10))
    end
    if self.shockT and self.shockT > 0 then
        love.graphics.setColor(Palette.red)
        local r = floor(self.def.recast.shock * (1 - self.shockT / 0.3))
        if r > 0 then pixelart.circleOutline(floor(e.x), floor(e.y), r) end
    end

    local s = self.strike
    if not s then return end
    local hot = s.stage == "hot"
    local colour = tellColour(s, time)

    if s.kind == "stamp" then
        -- The whole three by three, faintly, so the blank squares read as part
        -- of a face too; then the pips' cells.
        if not hot then
            love.graphics.setColor(Palette.graphite)
            box(s.x0, s.y0, s.cell * 3, s.cell * 3)
        end
        for _, c in ipairs(s.cells) do
            floorFace(c.x, c.y, s.cell, 1, hot, colour)
        end
    elseif s.kind == "net" then
        local f = s.fold or 0
        for _, c in ipairs(s.cells) do
            local size = floor(s.cell * (1 - f * 0.8))
            local x = c.x + (s.cx - s.cell / 2 - c.x) * f + (s.cell - size) / 2
            local y = c.y + (s.cy - s.cell / 2 - c.y) * f + (s.cell - size) / 2
            floorFace(x, y, size, c.n, s.stage == "hot", colour)
        end
    elseif s.kind == "checker" then
        local box0 = self:board()
        if box0 then
            local c = s.cell
            for cy = snap(box0.top, c), box0.bottom, c do
                for cx = snap(box0.left, c), box0.right, c do
                    if (floor(cx / c) + floor(cy / c)) % 2 == s.parity then
                        local x0, y0 = math.max(cx, box0.left), math.max(cy, box0.top)
                        local x1 = math.min(cx + c, box0.right)
                        local y1 = math.min(cy + c, box0.bottom)
                        if x1 > x0 and y1 > y0 then
                            if hot then
                                love.graphics.setColor(Palette.red)
                                love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
                            else
                                love.graphics.setColor(colour)
                                love.graphics.rectangle("fill", x0 + 2, y0 + 2, 2, 2)
                                love.graphics.rectangle("fill", x1 - 4, y1 - 4, 2, 2)
                                love.graphics.rectangle("fill", x1 - 4, y0 + 2, 2, 2)
                                love.graphics.rectangle("fill", x0 + 2, y1 - 4, 2, 2)
                            end
                        end
                    end
                end
            end
        end
    elseif s.kind == "spokes" then
        local def = self.def.spokes
        -- Through the count-in a ghost of the swing, over and over, so which
        -- way the spokes will go round is read before they do.
        local f = hot and math.min(1, s.age / s.hot) or (time * 2) % 1
        for k = 1, s.n do
            local a = spokeAngle(s, k, f)
            local len = def.length
            if self.box then len = reach({ arena = self.box }, s.x, s.y, a, def.length) end
            if hot then
                love.graphics.setColor(Palette.red)
                pixelart.band(s.x, s.y, s.x + math.cos(a) * len, s.y + math.sin(a) * len, def.width)
            else
                love.graphics.setColor(colour)
                dashes(s.x, s.y, a, len, time * 20)
            end
        end
    end
end

-- The part of the page a checkerboard covers: the box, or a screen's worth
-- round the die when there is none.
function DiceBoss:board()
    local b = self.box
    if b then return { left = b.left, top = b.top, right = b:right(), bottom = b:bottom() } end
    local e = self.e
    return { left = e.x - 240, top = e.y - 135, right = e.x + 240, bottom = e.y + 135 }
end

-- Over the crowd: the number it rolled, on a tag over it, while that number is
-- what is happening; and the stars of a fumble.
function DiceBoss:drawAir(time, e)
    if self.state == "show" or self.state == "fumble" then
        local text = tostring(self.roll or "")
        local w = Font.width(text) + 6
        local x = floor(e.x) - floor(w / 2)
        local y = floor(e.y) - e.radius - 18
        love.graphics.setColor(Palette.ink)
        love.graphics.rectangle("fill", x - 1, y - 1, w + 2, 11)
        love.graphics.setColor(self.state == "fumble" and Palette.blush or Palette.paper)
        love.graphics.rectangle("fill", x, y, w, 9)
        love.graphics.setColor(Palette.ink)
        Font.print(text, x + 3, y + 2)
    end
    if self.state == "fumble" then
        love.graphics.setColor(Palette.ink)
        for k = 0, 2 do
            local a = time * 3 + k * TAU / 3
            local sx = floor(e.x + math.cos(a) * 14)
            local sy = floor(e.y - e.radius - 4 + math.sin(a) * 4)
            love.graphics.rectangle("fill", sx - 1, sy, 3, 1)
            love.graphics.rectangle("fill", sx, sy - 1, 1, 3)
        end
    end
end

return DiceBoss
