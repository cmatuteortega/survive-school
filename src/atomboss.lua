-- The atom's mind: SCIENCE's encore, and the fight in the book about *orbits*.
--
-- The eye is a fight about the ground. The atom is the thing the eye was
-- looking at, and its fight is about the space round a body rather than the
-- floor under it: everything it does is an orbit, and an orbit is a ring you
-- are either inside or outside of.
--
-- **The orbits** go round it all the time, close in, each with an electron on
-- it that hurts to touch -- so it is never free to stand on top of, whatever
-- else it is doing. Between moves they tilt to a new lie (`Atom:shape`'s
-- `tiltTo`): a ring face on is a circle round it, tipped over it is an
-- ellipse, edge on it is a line through it.
--
-- **The sweep.** One orbit swells out across the box and goes hot. It is
-- drawn first where it is going to be -- a dashed red ring on the floor, already
-- swinging round the way it will swing -- and then it is there, a red band, for
-- a couple of seconds. How it swings is how it was tilted: face on it is a
-- wall round the atom you must not cross, tipped it is an ellipse sweeping
-- round, and edge on it is a bar turning like a lighthouse. Outwalkable at the
-- tip, barely, and safe outside it; the dashed ring is the whole of the tell.
--
-- **The throw.** An electron leaves its orbit and comes after you
-- (`home` on the shot, Game:updateEnemyShots): slower than you and slow to
-- turn, so it is dodged by a sidestep at the last moment rather than by
-- running, and it falls apart after a few seconds. Its orbit is empty until it
-- grows a new one.
--
-- **Fission.** At half its health it shudders, stretches, and comes apart into
-- two halves, each smaller and with fewer orbits than the whole -- and each a
-- boss in its own right, sharing what health was left. They come at you from
-- both sides, round you rather than at you, so there is never one side of the
-- box that is clear. The HUD's bar is the two of them together (`share`), and
-- the lesson is not over until the second goes down (`heir`, Game:killEnemy).
--
-- **Glue holds a tell.** A sweep or a throw still being counted in is dropped
-- and the atom rests, as the eye's tells are -- the tool-shaped counterplay
-- every boss in the book has.
--
-- The body is src/atom.lua, painted every frame; this file swells its orbits,
-- throws its electrons, splits it in two and reads where its rings are.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Atom = require("src.atom")
local util = require("src.util")

local AtomBoss = {}
AtomBoss.__index = AtomBoss

local TAU = math.pi * 2
local floor = math.floor

-- The entrance: how long its orbits take to form round it, during which they
-- hurt nobody -- it walks on as a nucleus, and *becomes* an atom.
local FORM_TIME = 1.2

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

function AtomBoss.new(def)
    return setmetatable({
        def = def.atom,
        state = "form", t = FORM_TIME,
        phase = 1,
        last = nil,
        group = nil, -- every piece of this atom, once it has walked on
        index = 1,   -- which half this is, once it has split
        e = nil,
    }, AtomBoss)
end

function AtomBoss:busy()
    return self.state ~= "idle"
end

--- the pieces -----------------------------------------------------------------

-- What is left of all of it, as a share of what walked on: the HUD's bar
-- (Hud's drawBoss), and the phase every piece reads.
function AtomBoss:share()
    local g = self.group
    if not g then return 1 end
    local hp = 0
    for _, m in ipairs(g.members) do
        if not m.gone then hp = hp + math.max(0, m.hp) end
    end
    return hp / g.whole
end

-- A piece still standing other than `e`, if there is one: who the HUD's bar is
-- hung off once `e` goes down (Game:killEnemy).
function AtomBoss:heir(e)
    local g = self.group
    if not g then return nil end
    for _, m in ipairs(g.members) do
        if m ~= e and not m.gone then return m end
    end
end

--- the loop -------------------------------------------------------------------

function AtomBoss:update(dt, game, e)
    self.e = e
    if not self.group then
        self.group = { whole = e.maxHp, members = { e }, split = false }
    end
    local body = e.nucleus
    if dt <= 0 then return end
    local g = self.group

    -- The phase: whole, split, and the last fifth of what is left of the two
    -- of them. Every piece reads the same share, so the halves turn together.
    local share = self:share()
    local phase = not g.split and 1 or share > 0.2 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        if phase >= 3 then
            Camera.knock(2)
            game.particles:burst(e.x, e.y, 16, Palette.red)
        end
    end
    body.hurt = 1 - share

    -- Half gone: it comes apart. Asked of the whole only -- a half never splits
    -- again -- and only once it is free to, so a split never cuts a sweep off
    -- half way through its swing.
    if not g.split and share <= self.def.fission.at
        and (self.state == "idle" or self.state == "resting") then
        self:clear(e)
        self.state, self.t = "fission", self.def.fission.time
        game:say("FISSION!")
    end

    body:update(dt)
    self:orbitHits(game, e)

    -- Glue answers a tell: a sweep or a throw still being counted in is
    -- dropped, and it rests.
    if e.frozen > 0 and (self.state == "sweepTell" or self.state == "throwTell") then
        self:clear(e)
        self:rest(e, 0.4)
    end

    self.t = self.t - dt
    self[self.state](self, dt, game, e)
end

-- Every orbit back to being an orbit.
function AtomBoss:clear(e)
    for _, ring in ipairs(e.nucleus.rings) do
        ring.state, ring.grow = nil, 1
    end
    self.ring, self.ghost = nil, nil
    e.nucleus.shake = 0
end

-- The window a move paid for, stood still, and a new lie for every orbit: the
-- tilt between attacks is how it says the next sweep will not be the last one.
function AtomBoss:rest(e, t)
    self.state, self.t = "resting", t
    e.drive = { hold = true }
    for _, ring in ipairs(e.nucleus.rings) do
        ring.tiltTo = 0.2 + love.math.random() * 1.2
    end
end

function AtomBoss:resting(dt, game, e)
    e.drive = { hold = true }
    if self.t <= 0 then
        self.state = "idle"
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.6
    end
end

--- the entrance ---------------------------------------------------------------

-- The orbits growing out of the nucleus, which is held where it walked on.
function AtomBoss:form(dt, game, e)
    e.drive = { hold = true }
    local f = 1 - math.max(0, self.t) / FORM_TIME
    for _, ring in ipairs(e.nucleus.rings) do ring.grow = f * f end
    if self.t <= 0 then
        for _, ring in ipairs(e.nucleus.rings) do ring.grow = 1 end
        self.state, self.t = "idle", 1.0
    end
end

--- walking about --------------------------------------------------------------

-- The whole walks at you. The halves walk *round* you, `keep` out and both
-- the same way round, aiming `turn` further round than they stand -- the
-- metronome's roam -- so, flung apart on either side of you, they stay either
-- side of you: between the two of them there is always one coming from behind.
-- Aiming at a point on a circle that turned on its own clock was the first
-- pass, and it had them cut across the circle and end up on top of you.
function AtomBoss:idle(dt, game, e)
    local player = game.player
    if self.group.split then
        local h = self.def.halves
        local a = math.atan2(e.y - player.y, e.x - player.x) + h.turn
        e.drive = { seek = true, x = player.x + math.cos(a) * h.keep,
                    y = player.y + math.sin(a) * h.keep }
        if game.arena then
            e.drive.x, e.drive.y = game.arena:clamp(e.drive.x, e.drive.y, e.radius)
        end
    else
        e.drive = nil
    end
    if self.t <= 0 and e.frozen <= 0 then self:choose(game, e) end
end

-- A sweep for whoever is inside its reach and a throw for whoever is out of
-- it, the last move marked down so it is never the same thing three times.
function AtomBoss:choose(game, e)
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local reach = pick(self.def.sweep.reach, self.phase)
    local w = {
        sweep = d < reach * 1.1 and 1.4 or 0.6,
        throw = d > 60 and 1.2 or 0.5,
    }
    if self.last then w[self.last] = w[self.last] * 0.35 end
    local move = love.math.random() * (w.sweep + w.throw) < w.sweep and "sweep" or "throw"
    self.last = move
    self[move .. "Start"](self, game, e)
end

--- the sweep ------------------------------------------------------------------

-- Which orbits swell: `count` of them, picked from the ones that are not empty.
-- Each gets the lie it will sweep at -- face on, tipped or edge on -- and the
-- way it will swing.
function AtomBoss:sweepStart(game, e)
    local s = self.def.sweep
    local rings = e.nucleus.rings
    local n = math.min(#rings, pick(s.count, self.phase))
    local first = love.math.random(1, #rings)
    self.swept = {}
    for k = 0, n - 1 do
        local ring = rings[(first + k - 1) % #rings + 1]
        ring.state = "tell"
        ring.tiltTo = s.tilts[love.math.random(1, #s.tilts)]
        ring.prec = (love.math.random() < 0.5 and -1 or 1) * pick(s.swing, self.phase)
        self.swept[#self.swept + 1] = ring
    end
    self.reach = pick(s.reach, self.phase)
    self.state, self.t = "sweepTell", pick(s.tell, self.phase)
    e.drive = { hold = true }
end

function AtomBoss:sweepTell(dt, game, e)
    e.drive = { hold = true }
    e.nucleus.shake = 0.5
    if self.t <= 0 then
        e.nucleus.shake = 0
        for _, ring in ipairs(self.swept) do ring.state = "hot" end
        self.state, self.t = "sweepHot", self.def.sweep.hold
        Camera.knock(1)
    end
end

-- Swollen out over `out` seconds and held there, then back in over the same.
-- The ring hurts for as long as it is out past its own orbit.
function AtomBoss:sweepHot(dt, game, e)
    e.drive = { hold = true }
    local s = self.def.sweep
    local held = s.hold - math.max(0, self.t)
    local f = math.min(1, held / s.out, math.max(0, self.t) / s.out)
    for _, ring in ipairs(self.swept) do
        ring.grow = 1 + (self.reach / ring.base - 1) * f
    end
    if self.t <= 0 then
        for _, ring in ipairs(self.swept) do ring.state, ring.grow = nil, 1 end
        self.swept = nil
        self:rest(e, pick(s.rest, self.phase))
    end
end

--- the throw ------------------------------------------------------------------

-- An electron leaves its orbit and comes after you. Counted in by the orbit it
-- is leaving blinking red.
function AtomBoss:throwStart(game, e)
    local rings = e.nucleus.rings
    self.throwing = {}
    local n = math.min(#rings, pick(self.def.throw.count, self.phase))
    local first = love.math.random(1, #rings)
    for k = 0, n - 1 do
        local ring = rings[(first + k - 1) % #rings + 1]
        if ring.emptyT <= 0 then
            ring.state = "tell"
            self.throwing[#self.throwing + 1] = ring
        end
    end
    self.state, self.t = "throwTell", pick(self.def.throw.tell, self.phase)
    e.drive = { hold = true }
end

function AtomBoss:throwTell(dt, game, e)
    e.drive = { hold = true }
    if self.t > 0 then return end
    local s = self.def.throw
    local cx, cy = e.nucleus:centre(e.x, e.y)
    for _, ring in ipairs(self.throwing) do
        ring.state = nil
        ring.emptyT = s.empty
        local px, py = Atom.point(ring, ring.phi)
        local x, y = cx + px, cy + py
        -- Off the way the electron was already going round, and then it turns
        -- for you: so it leaves on a curve rather than in a straight line at
        -- you, which is what makes it read as thrown off rather than fired.
        local qx, qy = Atom.point(ring, ring.phi + 0.05 * (ring.spin > 0 and 1 or -1))
        local dx, dy = util.normalize(qx - px, qy - py)
        game.shots[#game.shots + 1] = {
            x = x, y = y, dx = dx, dy = dy,
            speed = s.speed, damage = scaled(e, s.damage), life = s.life,
            sprite = "electron", radius = s.hit * e.reach, grow = e.grow,
            home = s.turn,
        }
        game.particles:burst(x, y, 4, Palette.red)
    end
    self.throwing = nil
    self:rest(e, pick(s.rest, self.phase))
end

--- fission --------------------------------------------------------------------

-- Shuddering and stretching, its orbits flung loose, and then two of it.
function AtomBoss:fission(dt, game, e)
    local f = self.def.fission
    e.drive = { hold = true }
    local k = 1 - math.max(0, self.t) / f.time
    e.nucleus.stretch = k * 0.55
    e.nucleus.shake = 1 + k
    for _, ring in ipairs(e.nucleus.rings) do ring.grow = 1 + k * 0.5 end
    if self.t <= 0 then self:split(game, e) end
end

-- Two halves, sharing what was left, thrown apart across the line to you so
-- you are between them from the first second.
--
-- The second is a whole new arrival made on the spot rather than one walked on
-- from the ring: the same row, at the scale the whole walked on with
-- (`Enemy.scale`), so it is exactly as hard as what it came out of. Required
-- here rather than at the top because src/enemy.lua requires this file.
function AtomBoss:split(game, e)
    local Enemy = require("src.enemy")
    local f, h = self.def.fission, self.def.halves
    local g = self.group
    g.split = true
    self.phase = 2

    local twin = Enemy.new(e.kind, e.x, e.y, e.scale)
    local each = math.max(1, floor(e.hp / 2 + 0.5))
    twin.hp, twin.maxHp = math.max(1, e.hp - each), e.maxHp
    e.hp = each
    game.enemies[#game.enemies + 1] = twin
    g.members[2] = twin

    local px, py = game.player.x, game.player.y
    local dx, dy = util.normalize(px - e.x, py - e.y)
    if dx == 0 and dy == 0 then dx, dy = 1, 0 end

    for i, m in ipairs({ e, twin }) do
        local brain = m.brain
        brain.group, brain.index, brain.phase = g, i, 2
        brain.e = m
        m.radius = h.radius
        m.nucleus:shape(h.size, h.rings, h.first, h.step)
        m.nucleus.stretch, m.nucleus.shake = 0, 0
        -- Flung apart at right angles to you, one each way.
        local side = i == 1 and 1 or -1
        brain.state, brain.t = "flung", f.fling
        m.drive = { dash = true, dx = -dy * side, dy = dx * side, speed = f.speed }
    end

    game.particles:burst(e.x, e.y, 40, Palette.red)
    game.particles:burst(e.x, e.y, 20, Palette.ink)
    Camera.knock(4)
end

-- In the air from the split, then down to it -- the second half resting a
-- beat longer, so the two of them are never counting the same move in at once.
function AtomBoss:flung(dt, game, e)
    if self.t <= 0 then self:rest(e, 0.5 + (self.index - 1) * 1.2) end
end

--- what hurts -----------------------------------------------------------------

-- How near (x, y) is to a ring at radius `r` round (cx, cy): the nearest of
-- the points the drawing plots, which is what makes it hurt where it is drawn.
local function nearRing(ring, cx, cy, r, x, y)
    local n = Atom.steps(r)
    local best = math.huge
    for i = 0, n - 1, 2 do
        local px, py = Atom.point(ring, i / n * TAU, r)
        local dx, dy = cx + px - x, cy + py - y
        local d = dx * dx + dy * dy
        if d < best then best = d end
    end
    return math.sqrt(best)
end

-- Every electron on an orbit, and every orbit that is swollen and hot. Through
-- Player:hurt like everything else, so its invulnerability window is the rate
-- limit and a ring passing over you is one hit, not one a frame. Nothing hurts
-- while it is still forming, and an orbit being told is drawn but not yet there.
function AtomBoss:orbitHits(game, e)
    if self.state == "form" then return end
    local player = game.player
    local cx, cy = e.nucleus:centre(e.x, e.y)
    local o, s = self.def.orbit, self.def.sweep
    for _, ring in ipairs(e.nucleus.rings) do
        if ring.state == "hot" then
            if ring.grow > 1.05 and nearRing(ring, cx, cy, ring.r, player.x, player.y)
                < player.radius + s.width / 2 then
                if player:hurt(scaled(e, s.damage)) then
                    game.particles:burst(player.x, player.y, 6, Palette.red)
                end
            end
        elseif ring.emptyT <= 0 and ring.state ~= "tell" then
            local px, py = Atom.point(ring, ring.phi)
            if util.len(cx + px - player.x, cy + py - player.y) < player.radius + o.hit then
                if player:hurt(scaled(e, o.damage)) then
                    game.particles:burst(player.x, player.y, 6, Palette.red)
                end
            end
        end
    end
end

--- drawing --------------------------------------------------------------------

-- Every piece's, from the one the game asks: the game hangs these off the boss
-- the HUD is reading (Game:draw), and a split atom is two.
local function each(self, fn)
    local g = self.group
    if not g then return fn(self, self.e) end
    for _, m in ipairs(g.members) do
        if not m.gone then fn(m.brain, m) end
    end
end

-- On the floor: where a swelling orbit is going to be, dashed and blinking
-- red, swinging round the way it will -- and an orbit about to throw its
-- electron, blinking.
function AtomBoss:drawGround(time)
    each(self, function(brain, e)
        if not e or not e.nucleus then return end
        local cx, cy = e.nucleus:centre(e.x, e.y)
        local on = floor(time * 8) % 2 == 0
        for _, ring in ipairs(e.nucleus.rings) do
            if ring.state == "tell" and brain.state == "sweepTell" then
                Atom.drawRing(ring, cx, cy, brain.reach,
                    on and Palette.red or Palette.blush, 1, 3, time * 20)
            end
        end
    end)
end

-- Over the crowd: the swollen orbits, as red bands with their electrons racing
-- round them, and an orbit about to throw, blinking with its electron on it.
function AtomBoss:drawAir(time, boss)
    each(self, function(brain, e)
        if not e or not e.nucleus then return end
        local body = e.nucleus
        local cx, cy = body:centre(e.x, e.y)
        local width = brain.def.sweep.width
        for _, ring in ipairs(body.rings) do
            if ring.state == "hot" then
                Atom.drawRing(ring, cx, cy, ring.r, Palette.red, width)
                for k = 0, 2 do
                    local px, py = Atom.point(ring, ring.phi + k * TAU / 3)
                    Atom.electron(cx + px, cy + py)
                end
            elseif ring.state == "tell" then
                local on = floor(time * 10) % 2 == 0
                Atom.drawRing(ring, cx, cy, ring.r, on and Palette.red or Palette.slate, 1, 2, 0)
                local px, py = Atom.point(ring, ring.phi)
                Atom.electron(cx + px, cy + py)
            end
        end
    end)
end

return AtomBoss
