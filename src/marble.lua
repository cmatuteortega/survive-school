-- ART's encore's mind: a block of marble with a bust in it, and the fight in
-- the book about *subtraction*.
--
-- The still life is the fight about light: three plaster solids you draw by
-- reading where the lamp is. What an art class does after it has drawn the
-- plaster is carve, and carving is the one way of making a thing that works by
-- taking away -- the statue is already in the block, and the sculptor's job is
-- everything that is not it. So that is what drops onto the page ten minutes
-- after the still life goes down: a block of marble straight out of the quarry.
--
-- **You are the chisel.** The body is a bust grown inside its block by a
-- margin (its model in src/solids.lua), through five stages -- the block, hewn,
-- roughed out, modelled, the finished bust -- and how far it has got is read
-- off its health: every hit takes a little marble off, and at each stage a chunk
-- of it comes away in a spray of grit and lies on the page. Until it has a head it stands square to the page; from the roughing out
-- on it turns to watch you, and the last third is the finished bust, polished
-- and alive, with its eyes open. A fight you can see the end of from the start:
-- what you are hitting is the shape of how far you have got.
--
-- **It is walked the way a heavy block is walked**: lifted an inch and dropped,
-- in short heavy hops that thud, a little nearer you each time -- higher and
-- quicker once it is alive. Every couple of seconds it flicks a chip at you, so
-- standing off is not free.
--
-- Everything else it does is a piece of it coming off, aimed:
--
--  - **The chisel.** A wedge is marked on the page from it to you and follows
--    you, then locks and blinks; then it is struck, and the chips fly down the
--    wedge in a fan too thick to walk through. Out of the wedge sideways is the
--    answer, and the next strike re-aims, so it is a step each strike: two in
--    the first third, three, then four.
--  - **The slab.** A slab splits off the side facing you and falls flat towards
--    you, as long as the block is tall. Its footprint is hatched on the page
--    from its foot to past you, following you and then locked; then it falls,
--    and under it is a hit. It lies there, cracks spreading through it, and from
--    the middle third it shatters when they meet: a ring of chips out of the
--    middle of it, so the slab you stepped beside is the next thing to step away
--    from. At the last third it splits two off, one after the other.
--  - **The rubble.** From the middle third: lumps knocked off the top of it are
--    thrown up and come down round you, each marked on the page as a ring where
--    it will land, the first on you and the rest about you, one after another.
--
-- What it has thrown goes on without it: a slab lying on the page cracks and
-- breaks whatever the block is doing, and the rubble in the air comes down.
--
-- **Glue sets it.** A glued block drops anything it was still counting in --
-- a wedge, a slab's footprint, the rubble not yet thrown -- and stands. What is
-- already off it is not the block any more, so it carries on.

local Palette = require("src.palette")
local Solids = require("src.solids")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Marble = {}
Marble.__index = Marble

local TAU = math.pi * 2
local floor = math.floor

-- The five stages, in the order they are carved (src/solids.lua).
local STAGES = { "block", "hewn", "roughed", "modelled", "bust" }

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new).
local function scaled(e, damage) return damage * e.damage / e.def.damage end

-- The floor under it, which is where everything it does to the page starts:
-- the origin is up in its chest, `foot` pixels above the page.
local function feet(e) return e.x, e.y + Solids.marble.foot end

-- The top of it on the page as it is drawn now, which gets lower as it is
-- carved.
local function crown(e)
    local rows = e.solid and e.solid:raster().rows
    return e.y + (rows and rows[1] and rows[1].j or -31)
end

function Marble.new(def)
    local m = def.marble
    return setmetatable({
        def = m,
        phase = 1,
        stage = 1,
        state = "idle",
        t = pick(m.cool, 1),
        hopT = pick(m.hop.every, 1) * 0.5,
        chipT = m.chip.every * 0.6,
        jump = nil,       -- the hop it is in the air for, if it is
        wedge = nil,      -- the chisel's wedge, while it is marked on the page
        mark = nil,       -- a slab's footprint, while it is counted in
        slabs = {},       -- slabs off it: falling, lying, cracking
        rocks = {},       -- rubble in the air
        debris = {},      -- what has come off it and lies on the page
    }, Marble)
end

function Marble:busy()
    return self.state ~= "idle"
end

-- How far it is carved, off its health, from 0 (the block) to 4 (the bust): a
-- whole number at each of the thresholds on the row and the way between them
-- between, so every hit takes some off and not only the hits that cross one.
function Marble:carving(e)
    local share = e.hp / e.maxHp
    local above = 1
    for k, at in ipairs(self.def.stages) do
        if share > at then
            return k - 1 + (above - share) / (above - at)
        end
        above = at
    end
    return #self.def.stages
end

-- Which stage it is at, off its health: the thresholds on the row, each one
-- passed a step further into the stone.
function Marble:stageFor(e)
    local share = e.hp / e.maxHp
    local stage = 1
    for k, at in ipairs(self.def.stages) do
        if share <= at then stage = k + 1 end
    end
    return stage
end

function Marble:update(dt, game, e)
    if dt <= 0 then return end

    -- What is off it goes on, glued or not.
    self:updateSlabs(dt, game, e)
    self:updateRocks(dt, game, e)
    for i = #self.debris, 1, -1 do
        local d = self.debris[i]
        d.age = d.age + dt
        if d.age > self.def.carve.lie then table.remove(self.debris, i) end
    end

    -- The phase, at the eye's thirds, and the stage under it.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    local stage = self:stageFor(e)
    if stage > self.stage then
        self.stage = stage
        self:carve(game, e)
    end
    if phase > self.phase then
        self.phase = phase
        Camera.knock(phase >= 3 and 4 or 3)
        game:say(phase == 2 and "ROUGHED OUT!" or "IT LIVES!")
    end
    if e.solid then e.solid:set("carve", self:carving(e)) end
    -- Square to the page until it has a head to turn; then it watches you.
    e.face = self.stage < 3 and math.pi / 2 or nil

    -- Set: down where it is, and anything it was counting in is dropped.
    if e.frozen > 0 then
        if self.state ~= "idle" and self.state ~= "rest" then
            self.wedge, self.mark = nil, nil
            self.state, self.t = "rest", 0.4
        end
        self.jump = nil
        e.hop = 0
        e.drive = { hold = true }
        return
    end

    self.t = self.t - dt
    e.drive = { hold = true }
    if self.jump then self:fly(dt, game, e) end
    self[self.state](self, dt, game, e)
end

-- A chunk comes away: grit off it, the page jumps, and the chunks lie where
-- they land. Nothing here hurts -- it is the one thing it does that is yours.
function Marble:carve(game, e)
    local x, y = feet(e)
    local top = crown(e)
    for k, colour in ipairs({ Palette.paper, Palette.graphite, Palette.slate }) do
        game.particles:burst(e.x, e.y - 8, 14 - 3 * k, colour)
    end
    for _ = 1, 16 do game.particles:crumb(e.x, (top + y) / 2, nil, nil, e.radius, Palette.graphite) end
    for _ = 1, self.def.carve.chunks do
        local a = love.math.random() * TAU
        local d = e.radius + 6 + love.math.random() * 22
        self.debris[#self.debris + 1] = {
            x = x + math.cos(a) * d, y = y + math.sin(a) * d * 0.6,
            r = love.math.random(1, 3), age = 0,
        }
    end
    Camera.knock(3)
    Sfx.play("stamp", 0.8)
end

--- getting about --------------------------------------------------------------

function Marble:leap(e, x, y, time, high, land)
    self.jump = { x0 = e.x, y0 = e.y, x1 = x, y1 = y, time = time, t = 0,
                  high = high, land = land }
end

function Marble:fly(dt, game, e)
    local j = self.jump
    j.t = j.t + dt
    local f = math.min(1, j.t / j.time)
    e.x = j.x0 + (j.x1 - j.x0) * f
    e.y = j.y0 + (j.y1 - j.y0) * f
    e.headX, e.headY = util.normalize(j.x1 - j.x0, j.y1 - j.y0)
    e.hop = floor(4 * j.high * f * (1 - f) + 0.5)
    -- Off the page is not touching you.
    if e.hop > 3 then e.hitCooldown = math.max(e.hitCooldown, 0.1) end
    if f >= 1 then
        self.jump = nil
        e.hop = 0
        if j.land then j.land(self, game, e) end
    end
end

function Marble:idle(dt, game, e)
    local def = self.def
    if not self.jump then
        self.hopT = self.hopT - dt
        if self.hopT <= 0 then
            -- A hop at you: lifted, a short way along the line to you, and
            -- dropped with a thud.
            self.hopT = pick(def.hop.every, self.phase)
            local p = game.player
            local dx, dy, d = util.normalize(p.x - e.x, p.y - e.y)
            local step = math.min(def.hop.reach, math.max(0, d - 12))
            local x, y = e.x + dx * step, e.y + dy * step
            if game.arena then x, y = game.arena:clamp(x, y, e.radius + 2) end
            self:leap(e, x, y, def.hop.time, pick(def.hop.high, self.phase), function(s, g, en)
                local fx, fy = feet(en)
                for _ = 1, 4 do g.particles:crumb(fx, fy, nil, nil, en.radius * 0.6, Palette.graphite) end
                Camera.knock(1)
            end)
        end
    end

    self.chipT = self.chipT - dt
    if self.chipT <= 0 then
        self.chipT = def.chip.every
        self:chip(game, e, math.atan2(game.player.y - e.y, game.player.x - e.x), def.chip)
    end

    if self.t <= 0 and not self.jump then self:choose(game, e) end
end

-- One chip of marble off it, flying at `a`.
function Marble:chip(game, e, a, c, x, y, speed)
    game.shots[#game.shots + 1] = {
        x = x or e.x, y = y or e.y, dx = math.cos(a), dy = math.sin(a),
        speed = speed or c.speed, damage = scaled(e, c.damage), life = c.life,
        sprite = "marbleChip", radius = c.hit * e.reach, grow = e.grow,
    }
end

-- The choice: the chisel for someone in front of it, the slab for someone
-- within a slab's length, the rubble once the middle third has unlocked it --
-- and never the same thing twice running if there is anything else.
function Marble:choose(game, e)
    local def = self.def
    local fx, fy = feet(e)
    local d = util.len(game.player.x - fx, game.player.y - fy)
    local w = {
        chisel = 1.2,
        slab = d < def.slab.length + 20 and 1.4 or 0.5,
    }
    if self.phase >= def.rubble.from then w.rubble = d > 60 and 1.4 or 1.0 end
    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.15 end

    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "chisel"
    for _, name in ipairs({ "chisel", "slab", "rubble" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.last = move
    self["start_" .. move](self, game, e)
end

function Marble:rest(dt, game, e)
    if self.t <= 0 then
        self.state, self.t = "idle", pick(self.def.cool, self.phase) + love.math.random() * 0.4
    end
end

function Marble:restFor(t)
    self.state, self.t = "rest", t
    self.wedge, self.mark = nil, nil
end

--- the chisel -----------------------------------------------------------------

function Marble:start_chisel(game, e)
    local c = self.def.chisel
    self.state = "chisel"
    self.strikes = pick(c.strikes, self.phase)
    self:aimWedge(game, e)
end

function Marble:aimWedge(game, e)
    local c = self.def.chisel
    self.t = pick(c.tell, self.phase)
    self.wedge = { a = math.atan2(game.player.y - e.y, game.player.x - e.x), locked = false }
end

function Marble:chisel(dt, game, e)
    local c = self.def.chisel
    local w = self.wedge
    if self.t > c.lock then
        -- Following you, until the last moment before the strike.
        w.a = math.atan2(game.player.y - e.y, game.player.x - e.x)
        return
    end
    w.locked = true
    if self.t > 0 then return end

    -- Struck: a fan of chips down the wedge, edge to edge.
    local n = pick(c.count, self.phase)
    for k = 0, n - 1 do
        local a = w.a - c.arc / 2 + c.arc * k / (n - 1)
        -- A little ragged in speed, so the fan arrives as a spray rather than
        -- as a line of beads.
        self:chip(game, e, a, c, nil, nil, c.speed * (0.85 + 0.3 * love.math.random()))
    end
    game.particles:burst(e.x + math.cos(w.a) * e.radius, e.y + math.sin(w.a) * e.radius, 8,
        Palette.graphite)
    Camera.knock(2)
    Sfx.play("stapler", 0.7)

    self.strikes = self.strikes - 1
    if self.strikes > 0 then
        self:aimWedge(game, e)
        self.t = pick(c.again, self.phase)
    else
        self:restFor(pick(c.rest, self.phase))
    end
end

--- the slab -------------------------------------------------------------------

-- The four corners of a slab lying from the floor point (x, y) along angle a.
local function slabQuad(x, y, a, near, len, width)
    local dx, dy = math.cos(a), math.sin(a)
    local px, py = -dy * width / 2, dx * width / 2
    local x0, y0 = x + dx * near, y + dy * near
    local x1, y1 = x + dx * (near + len), y + dy * (near + len)
    return { x0 + px, y0 + py, x1 + px, y1 + py, x1 - px, y1 - py, x0 - px, y0 - py }
end

-- Whether (px, py) is on a slab, give or take `pad`.
local function onSlab(s, px, py, pad)
    local dx, dy = math.cos(s.a), math.sin(s.a)
    local rx, ry = px - s.x, py - s.y
    local along = rx * dx + ry * dy
    local across = math.abs(-rx * dy + ry * dx)
    return along >= s.near - pad and along <= s.near + s.len + pad and across <= s.width / 2 + pad
end

function Marble:start_slab(game, e)
    self.state = "slab"
    self.slabsLeft = pick(self.def.slab.count, self.phase)
    self:markSlab(game, e)
end

function Marble:markSlab(game, e)
    local s = self.def.slab
    self.t = pick(s.tell, self.phase)
    local fx, fy = feet(e)
    self.mark = { x = fx, y = fy, a = math.atan2(game.player.y - fy, game.player.x - fx),
                  near = e.radius * 0.5, len = s.length, width = s.width, locked = false }
end

function Marble:slab(dt, game, e)
    local s = self.def.slab
    local m = self.mark
    if self.t > s.lock then
        m.a = math.atan2(game.player.y - m.y, game.player.x - m.x)
        return
    end
    m.locked = true
    if self.t > 0 then return end

    -- Split off, and falling: the slab is its own thing from here.
    m.state, m.t = "fall", s.fall
    m.damage = scaled(e, s.damage)
    m.burst = pick(s.burst, self.phase)
    m.seed = love.math.random(1, 1000)
    self.slabs[#self.slabs + 1] = m
    self.mark = nil
    Sfx.play("tick", 0.6)

    self.slabsLeft = self.slabsLeft - 1
    if self.slabsLeft > 0 then
        self:markSlab(game, e)
        self.t = s.again
    else
        self:restFor(pick(s.rest, self.phase))
    end
end

function Marble:updateSlabs(dt, game, e)
    local def = self.def.slab
    local p = game.player
    for i = #self.slabs, 1, -1 do
        local s = self.slabs[i]
        s.t = s.t - dt
        if s.state == "fall" and s.t <= 0 then
            -- Down: whoever is under it is hit, and the page jumps.
            if onSlab(s, p.x, p.y, p.radius * 0.5) and p:hurt(s.damage) then
                game.particles:burst(p.x, p.y, 8, Palette.red)
            end
            local mx, my = s.x + math.cos(s.a) * (s.near + s.len / 2), s.y + math.sin(s.a) * (s.near + s.len / 2)
            for _ = 1, 14 do game.particles:crumb(mx, my, nil, nil, s.len * 0.4, Palette.graphite) end
            Camera.knock(4)
            Sfx.play("stamp", 0.7)
            s.state, s.t = "lie", pick(def.lie, self.phase)
        elseif s.state == "lie" and s.t <= 0 then
            -- And breaks: grit, and from the middle third a ring of chips out
            -- of the middle of it, turned a little each time.
            local mx, my = s.x + math.cos(s.a) * (s.near + s.len / 2), s.y + math.sin(s.a) * (s.near + s.len / 2)
            game.particles:burst(mx, my, 16, Palette.paper)
            game.particles:burst(mx, my, 10, Palette.slate)
            local n = s.burst or 0
            local turn = love.math.random() * TAU
            for k = 1, n do
                self:chip(game, e, turn + k / n * TAU, def.chips, mx, my)
            end
            for _ = 1, 4 do
                self.debris[#self.debris + 1] = {
                    x = mx + (love.math.random() - 0.5) * s.len * 0.8 * math.cos(s.a),
                    y = my + (love.math.random() - 0.5) * s.len * 0.8 * math.sin(s.a),
                    r = love.math.random(1, 3), age = 0,
                }
            end
            Sfx.play("stapler", 0.6)
            table.remove(self.slabs, i)
        end
    end
end

--- the rubble -----------------------------------------------------------------

function Marble:start_rubble(game, e)
    local r = self.def.rubble
    self.state = "rubble"
    self.t = r.wind
    -- Lumps up out of the top of it, and everyone gets a moment to see them go.
    Camera.knock(2)
    game.particles:burst(e.x, crown(e) + 6, 12, Palette.graphite)
    Sfx.play("stapler", 0.9)
end

function Marble:rubble(dt, game, e)
    local r = self.def.rubble
    if self.t > 0 then return end
    local p = game.player
    local n = pick(r.count, self.phase)
    for k = 1, n do
        -- The first on you, the rest about you.
        local x, y = p.x, p.y
        if k > 1 then
            local a = love.math.random() * TAU
            local d = r.near + love.math.random() * (r.spread - r.near)
            x, y = x + math.cos(a) * d, y + math.sin(a) * d
        end
        if game.arena then x, y = game.arena:clamp(x, y, 4) end
        local land = r.aim + (k - 1) * r.gap
        self.rocks[#self.rocks + 1] = { x = x, y = y, t = land, flight = land,
                                        damage = scaled(e, r.damage) }
    end
    self:restFor(pick(r.rest, self.phase))
end

function Marble:updateRocks(dt, game, e)
    local r = self.def.rubble
    local p = game.player
    for i = #self.rocks, 1, -1 do
        local k = self.rocks[i]
        k.t = k.t - dt
        if k.t <= 0 then
            if util.len(p.x - k.x, p.y - k.y) < r.radius + p.radius * 0.5 and p:hurt(k.damage) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
            for _ = 1, 6 do game.particles:crumb(k.x, k.y, nil, nil, r.radius * 0.6, Palette.graphite) end
            game.particles:burst(k.x, k.y, 6, Palette.paper)
            self.debris[#self.debris + 1] = { x = k.x, y = k.y, r = 3, age = 0 }
            Camera.knock(1)
            Sfx.play("stamp", 1.2)
            table.remove(self.rocks, i)
        end
    end
end

--- drawing --------------------------------------------------------------------

-- A dashed line, for anything counted in.
local function dashes(x0, y0, x1, y1, shift)
    local dx, dy = x1 - x0, y1 - y0
    local n = math.max(1, floor(math.max(math.abs(dx), math.abs(dy))))
    for i = 0, n do
        if floor((i + shift) / 3) % 2 == 0 then
            love.graphics.rectangle("fill", floor(x0 + dx * i / n), floor(y0 + dy * i / n), 1, 1)
        end
    end
end

local function dashedQuad(q, shift)
    for k = 1, 7, 2 do
        local n = k + 2 > 8 and 1 or k + 2
        dashes(q[k], q[k + 1], q[n], q[n + 1], shift)
    end
end

-- A lump of marble lying on the page: a pale chip with an ink edge.
local function lump(x, y, r)
    x, y = floor(x), floor(y)
    love.graphics.setColor(Palette.ink)
    love.graphics.rectangle("fill", x - r, y - 1, r * 2 + 1, 3)
    love.graphics.rectangle("fill", x - r + 1, y - 2, r * 2 - 1, 5)
    love.graphics.setColor(Palette.paper)
    love.graphics.rectangle("fill", x - r + 1, y - 1, r * 2 - 1, 2)
    love.graphics.setColor(Palette.graphite)
    love.graphics.rectangle("fill", x - r + 1, y + 1, r * 2 - 1, 1)
end

-- On the floor: what has come off it, the slabs lying there, and what is being
-- counted in.
function Marble:drawGround(time)
    local shift = floor(time * 20)
    local blink = floor(time * 8) % 2 == 0
    local lie = self.def.carve.lie

    for _, d in ipairs(self.debris) do
        -- Faded by dropping out, not by alpha: the last second blinks.
        if d.age < lie - 1 or floor(d.age * 10) % 2 == 0 then lump(d.x, d.y, d.r) end
    end

    -- The slabs: falling (swinging down from upright to flat, so its far end
    -- comes in over the footprint), lying, and cracking before they break.
    local def = self.def.slab
    for _, s in ipairs(self.slabs) do
        local len = s.len
        if s.state == "fall" then
            local f = 1 - math.max(0, s.t) / def.fall
            len = math.max(2, s.len * f * f)
            love.graphics.setColor(Palette.red)
            dashedQuad(slabQuad(s.x, s.y, s.a, s.near, s.len, s.width), shift)
        end
        local q = slabQuad(s.x, s.y, s.a, s.near, len, s.width)
        local ys = { q[2], q[4], q[6], q[8] }
        local y0, y1 = math.min(unpack(ys)), math.max(unpack(ys))
        love.graphics.setColor(Palette.paper)
        pixelart.fillPolygon(q, y0, y1, function(x, y, w) love.graphics.rectangle("fill", x, y, w, 1) end)
        love.graphics.setColor(Palette.ink)
        for k = 1, 7, 2 do
            local n = k + 2 > 8 and 1 or k + 2
            pixelart.line(q[k], q[k + 1], q[n], q[n + 1])
        end
        -- A vein along it, because it is the same stone.
        local dx, dy = math.cos(s.a), math.sin(s.a)
        local px, py = -dy, dx
        local vx0 = s.x + dx * (s.near + 3) + px * (s.width * 0.2)
        local vx1 = s.x + dx * (s.near + len - 3) - px * (s.width * 0.15)
        local vy0 = s.y + dy * (s.near + 3) + py * (s.width * 0.2)
        local vy1 = s.y + dy * (s.near + len - 3) - py * (s.width * 0.15)
        love.graphics.setColor(Palette.blush)
        pixelart.line(vx0, vy0, vx1, vy1)
        -- The cracks, once it is lying: growing in from both ends over the time
        -- it lies, red for the last of it.
        if s.state == "lie" then
            local total = pick(def.lie, self.phase)
            local f = 1 - math.max(0, s.t) / total
            love.graphics.setColor((s.t < def.crack and blink) and Palette.red or Palette.slate)
            local mid = s.near + s.len / 2
            for k = -1, 1, 2 do
                local from = mid + k * s.len / 2
                local x, y = s.x + dx * from, s.y + dy * from
                local steps = floor(6 * f)
                local wob = s.seed + k * 7
                for j = 1, steps do
                    local along = from - k * s.len / 2 * j / 6
                    local off = math.sin(wob + j * 2.3) * s.width * 0.3
                    local nx, ny = s.x + dx * along + px * off, s.y + dy * along + py * off
                    pixelart.line(x, y, nx, ny)
                    x, y = nx, ny
                end
            end
        end
    end

    -- The slab being counted in: its footprint, hatched, following you, then
    -- locked and blinking.
    local m = self.mark
    if m then
        local q = slabQuad(m.x, m.y, m.a, m.near, m.len, m.width)
        love.graphics.setColor((m.locked and blink) and Palette.red or Palette.slate)
        dashedQuad(q, shift)
        local ys = { q[2], q[4], q[6], q[8] }
        pixelart.fillPolygon(q, math.min(unpack(ys)), math.max(unpack(ys)), function(x, y, w)
            for i = x, x + w - 1 do
                if (i + y + floor(shift / 4)) % 5 == 0 and y % 2 == 0 then
                    love.graphics.rectangle("fill", i, y, 1, 1)
                end
            end
        end)
    end

    -- The rubble's rings, where each lump will come down: closing in, red for
    -- the last of it.
    local r = self.def.rubble
    for _, k in ipairs(self.rocks) do
        local f = 1 - math.max(0, k.t) / k.flight
        love.graphics.setColor((k.t < 0.3 and blink) and Palette.red or Palette.slate)
        pixelart.circleOutline(k.x, k.y, r.radius)
        love.graphics.setColor(Palette.graphite)
        pixelart.circleFill(k.x, k.y, floor(1 + f * (r.radius - 4)))
    end
end

-- Over the crowd: the chisel's wedge, the rubble in the air, and the bust's
-- eyes once it is alive.
function Marble:drawAir(time, e)
    local shift = floor(time * 20)
    local w = self.wedge
    if w then
        local c = self.def.chisel
        local blink = floor(time * 8) % 2 == 0
        love.graphics.setColor((w.locked and blink) and Palette.red or Palette.slate)
        local r0 = e.radius + 2
        for k = -1, 1, 2 do
            local a = w.a + k * c.arc / 2
            dashes(e.x + math.cos(a) * r0, e.y + math.sin(a) * r0,
                e.x + math.cos(a) * c.length, e.y + math.sin(a) * c.length, shift)
        end
        local steps = 10
        for i = 0, steps do
            local a = w.a - c.arc / 2 + c.arc * i / steps
            love.graphics.rectangle("fill", floor(e.x + math.cos(a) * c.length),
                floor(e.y + math.sin(a) * c.length), 1, 1)
        end
    end

    local r = self.def.rubble
    for _, k in ipairs(self.rocks) do
        local f = 1 - math.max(0, k.t) / k.flight
        local h = floor(r.high * (1 - f * f))
        if h < 240 then
            local x, y = floor(k.x), floor(k.y - h)
            love.graphics.setColor(Palette.ink)
            pixelart.circleFill(x, y, 4)
            love.graphics.setColor(Palette.paper)
            pixelart.circleFill(x, y, 3)
            love.graphics.setColor(Palette.graphite)
            love.graphics.rectangle("fill", x - 2, y + 1, 4, 1)
        end
    end

    -- Alive: the finished bust opens its eyes, red, wherever they are in the
    -- picture it is drawn as (the picture says, and whether they can be seen).
    -- Not while it is lit by a hit: a white flash with two red eyes in it reads
    -- as the eyes being hit.
    if self.stage >= #STAGES and e.solid and e.flash <= 0 then
        local eyes = e.solid:raster().eyes
        if eyes then
            local _, x, y = e:footing()
            love.graphics.setColor(Palette.red)
            for _, p in ipairs(eyes) do
                love.graphics.rectangle("fill", floor(x) + p[1], floor(y) + p[2], 1, 1)
            end
        end
    end
end

-- Everything it has on the page goes with it.
function Marble:sweep(game)
    self.slabs, self.rocks, self.wedge, self.mark = {}, {}, nil, nil
end

return Marble
