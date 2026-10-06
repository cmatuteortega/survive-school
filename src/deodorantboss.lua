-- The deodorant's mind: P.E.'s encore, and the fight in the book about *the air*.
--
-- The whistle is a fight about what is in the air -- notes and jacks, things you
-- can see coming and step round. The deodorant is what the changing room smells
-- of once the whistle has blown: a can of body spray, and its fight is about the
-- air itself. Nothing it does is a thing you dodge. It is a cloud you get out of,
-- wait out or clear, because every other boss's hazard stays where it was put
-- and this one does not.
--
-- **The cloud.** The whole fight runs off one grid laid over the box, a cell
-- every CELL pixels, holding how thick the spray is there. Every frame it
-- spreads into its neighbours and thins out, so a puff blooms, softens and goes,
-- and it is *pushed* by what moves through it:
--
--  - **You.** Walking through it parts it round you -- what is in front of you
--    is pushed aside -- so a thin cloud is something you can wade, and standing
--    still in one is the one way to let it settle on you.
--  - **What you kill in it.** Anything going down inside it takes the air round
--    it with it, so a build that kills fast blows holes in the cloud to breathe in.
--  - **The draught**, below, which pushes all of it at once.
--
-- Thin (blush) it slows you, because you are coughing; thick (red) it hurts.
-- That is the whole of its grammar, and the colours say it: red is theirs, and
-- red mist is the mist to be out of.
--
-- **The spritz.** It walks at you and puffs at you every couple of seconds: a
-- puff goes out along its throw and blooms where it lands, so the air round it
-- slowly fills up. Now and then -- most of all in the first third -- it fans
-- three at you at once.
--
-- **The full body spray.** It plants, the fan it is about to cover dotted on the
-- floor in front of it, and holds the button down while it turns across the fan,
-- laying a curtain of mist behind the stream. The answer is the metronome's --
-- out of the fan, behind the can or past the end of the stream -- with a cost the
-- metronome's sweep did not have: the curtain stays, and spreads, and comes on.
--
-- **The draught** (from the second third). Someone opens the changing room door.
-- Streaks come in at one edge of the box, and then a wind blows across it and
-- pushes every cloud on the page -- and you, and the crowd -- one way, while the
-- can puffs into it from upwind so a plume rolls down on you. The only move in the
-- book that moves the player: walk across the wind, out of the plume.
--
-- **Shake well** (the last third). It rattles -- the clack of the ball inside --
-- with a circle following you on the floor, then locked, and then empties a
-- great burst into the circle: thick mist from edge to edge of it. Be outside it.
--
-- **The leak** (the last third). A dent pops and it spins on its own jet,
-- skittering about the box on it, spraying out a spiral. Its reach is dotted
-- round it for as long as it spins: keep out of the circle.
--
-- **Glue clogs the nozzle.** A glued can drops whatever it was going to spray,
-- and cannot: but the pressure builds in it while it is held -- it swells -- and
-- when it is let go it goes off all at once round itself. The one glue in the
-- book with a price on it.
--
-- The body is src/deodorant.lua, painted every frame; this file turns it, keeps
-- the cloud, and owns everything it lets go of: the puffs, the stream, the wind.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local DeoBoss = {}
DeoBoss.__index = DeoBoss

local TAU = math.pi * 2
local floor, ceil, abs, max, min, cos, sin, sqrt =
    math.floor, math.ceil, math.abs, math.max, math.min, math.cos, math.sin, math.sqrt

-- The entrance: dropped onto the page (Game:dropIn), then the cap comes off and
-- it gives the air a test spray.
local ENTER_TIME = 1.0
-- The cloud's grid: a cell every CELL pixels, and never thicker than MOST, so a
-- spot sprayed for a long time is no worse than one sprayed well.
local CELL, MOST = 8, 1.3
-- What is too thin to keep: below this a cell is clean air.
local CLEAN = 0.004
-- The longest step the cloud is moved on in one go; a long frame is cut into
-- several, which keeps the spreading stable at any frame rate.
local STEP = 1 / 40
-- How long one streak of the draught takes to cross the screen, at most.
local STREAK_LIFE = 0.9

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

--- the cloud --------------------------------------------------------------------

-- The grid over the box, or over a page-sized patch round where it walked on if
-- there is no box.
local function newCloud(box, x, y)
    local left, top, w, h
    if box then
        left, top, w, h = box.left, box.top, box.w, box.h
    else
        w, h = 480, 270
        left, top = floor(x - w / 2), floor(y - h / 2)
    end
    local cols, rows = ceil(w / CELL), ceil(h / CELL)
    local d, tmp = {}, {}
    for i = 1, cols * rows do d[i], tmp[i] = 0, 0 end
    return { left = left, top = top, w = w, h = h, cols = cols, rows = rows,
             d = d, tmp = tmp, any = false }
end

-- How thick it is at a point on the page: read between the four nearest cells,
-- so a cloud has soft edges rather than square ones.
local function sample(c, x, y)
    local gx = (x - c.left) / CELL + 0.5
    local gy = (y - c.top) / CELL + 0.5
    local c0, r0 = floor(gx), floor(gy)
    local fx, fy = gx - c0, gy - r0
    local cols, rows, d = c.cols, c.rows, c.d
    local c1, r1 = c0 + 1, r0 + 1
    if c0 < 1 then c0 = 1 end
    if r0 < 1 then r0 = 1 end
    if c1 > cols then c1 = cols end
    if r1 > rows then r1 = rows end
    if c0 > cols then c0 = cols end
    if r0 > rows then r0 = rows end
    if c1 < 1 then c1 = 1 end
    if r1 < 1 then r1 = 1 end
    local a = d[(r0 - 1) * cols + c0]
    local b = d[(r0 - 1) * cols + c1]
    local cc = d[(r1 - 1) * cols + c0]
    local dd = d[(r1 - 1) * cols + c1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + dd * fx) * fy
end

-- Every cell within `radius` of a point, and how far its middle is from it.
local function eachCell(c, x, y, radius, fn)
    local c0 = max(1, floor((x - radius - c.left) / CELL) + 1)
    local c1 = min(c.cols, floor((x + radius - c.left) / CELL) + 1)
    local r0 = max(1, floor((y - radius - c.top) / CELL) + 1)
    local r1 = min(c.rows, floor((y + radius - c.top) / CELL) + 1)
    for r = r0, r1 do
        local cy = c.top + (r - 0.5) * CELL
        for col = c0, c1 do
            local cx = c.left + (col - 0.5) * CELL
            local dist = sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
            if dist <= radius then fn((r - 1) * c.cols + col, dist) end
        end
    end
end

-- Spray put into the air round a point. Falling off from the middle to nothing
-- at `radius`; or, with `soft`, even out to `radius` and falling off over `soft`
-- beyond it -- the shape of a burst you were shown the edge of.
local function add(c, x, y, amount, radius, soft)
    local d = c.d
    local reach = radius + (soft or 0) + CELL * 0.5
    eachCell(c, x, y, reach, function(i, dist)
        local w
        if soft then
            w = util.clamp((radius + soft - dist) / soft, 0, 1)
        else
            w = max(0, 1 - dist / (radius + CELL * 0.5))
        end
        if w > 0 then d[i] = min(MOST, d[i] + amount * w) end
    end)
    c.any = true
end

-- Taken out of the air round a point: `k` of it at the middle, less outwards.
local function clear(c, x, y, radius, k)
    local d = c.d
    eachCell(c, x, y, radius, function(i, dist)
        d[i] = d[i] * (1 - k * (1 - dist / (radius + 1)))
    end)
end

-- Pushed aside: `f` of what is within `radius` of a point taken out and laid
-- round the ring just outside it. Something walking through mist does not
-- clear it, it moves it -- which is why a wade leaves a wake rather than a path.
local function part(c, x, y, radius, f)
    if f <= 0 then return end
    local d = c.d
    local moved, ring = 0, {}
    eachCell(c, x, y, radius + CELL * 1.5, function(i, dist)
        if dist <= radius then
            local a = d[i] * f
            d[i] = d[i] - a
            moved = moved + a
        else
            ring[#ring + 1] = i
        end
    end)
    if moved > 0 and #ring > 0 then
        local each = moved / #ring
        for _, i in ipairs(ring) do d[i] = min(MOST, d[i] + each) end
    end
end

-- One step of the air: spread into the neighbours (a wall gives back what it is
-- leant on with), thin out, and -- with a wind -- be carried along it, fresh air
-- coming in at the edge it blows from and the mist going out at the far one.
local function stepCloud(c, h, spread, life, wx, wy)
    local d, tmp, cols, rows = c.d, c.tmp, c.cols, c.rows
    local k = spread * h
    local keep = 1 - h / life
    local any = false
    for r = 1, rows do
        local base = (r - 1) * cols
        for col = 1, cols do
            local i = base + col
            local v = d[i]
            local l = col > 1 and d[i - 1] or v
            local rt = col < cols and d[i + 1] or v
            local u = r > 1 and d[i - cols] or v
            local dn = r < rows and d[i + cols] or v
            local nv = (v + k * (l + rt + u + dn - 4 * v)) * keep
            if nv < CLEAN then nv = 0 else any = true end
            tmp[i] = nv
        end
    end
    c.d, c.tmp = tmp, d
    d, tmp = c.d, c.tmp

    if any and (wx ~= 0 or wy ~= 0) then
        -- Where the air in each cell was a step ago, read back up the wind.
        local sx, sy = wx * h / CELL, wy * h / CELL
        for r = 1, rows do
            local base = (r - 1) * cols
            local gy = r - sy
            for col = 1, cols do
                local gx = col - sx
                local v = 0
                if gx >= 1 and gx <= cols and gy >= 1 and gy <= rows then
                    local c0, r0 = floor(gx), floor(gy)
                    local fx, fy = gx - c0, gy - r0
                    local c1, r1 = min(cols, c0 + 1), min(rows, r0 + 1)
                    local a = d[(r0 - 1) * cols + c0]
                    local b = d[(r0 - 1) * cols + c1]
                    local cc = d[(r1 - 1) * cols + c0]
                    local dd = d[(r1 - 1) * cols + c1]
                    v = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + dd * fx) * fy
                end
                tmp[base + col] = v
            end
        end
        c.d, c.tmp = tmp, d
    end
    c.any = any
end

--- the brain --------------------------------------------------------------------

function DeoBoss.new(def)
    return setmetatable({
        def = def.deodorant,
        state = "enter", t = ENTER_TIME,
        phase = 1,
        last = nil,
        cloud = nil,
        puffs = {},    -- spritzes in flight, harmless until they bloom
        streaks = {},  -- what the draught draws going across the page
        stream = nil,  -- the spray coming out of it this frame, for the drawing
        fan = nil,     -- the full body spray's fan, counted in and then swept
        wind = nil,    -- the draught: which way, and how long it has left
        target = nil,  -- shake well's circle
        spinning = false,
        spritzT = 1.5,
        clog = 0, clogged = false,
        chokeT = 0,
        lastPX = nil, lastPY = nil,
        coughT = 0,
        e = nil,
    }, DeoBoss)
end

function DeoBoss:busy()
    return self.state ~= "idle"
end

-- Something of the crowd went down (Game:killEnemy): if it was in the mist, the
-- mist round it goes with it.
function DeoBoss:onKill(game, o)
    local c = self.cloud
    if not c or not c.any then return end
    if sample(c, o.x, o.y) < self.def.cloud.thin then return end
    clear(c, o.x, o.y, self.def.cloud.clear, 0.9)
    game.particles:burst(o.x, o.y, 4, Palette.blush)
end

--- the loop -------------------------------------------------------------------

function DeoBoss:update(dt, game, e)
    self.e, self.box = e, game.arena
    local body = e.deodorant
    if not self.cloud then self.cloud = newCloud(game.arena, e.x, e.y) end
    if dt <= 0 then return end
    local def = self.def

    -- The phase, at the eye's thirds, and said out loud.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        game:say(phase >= 3 and "SHAKE WELL!" or "EXTRA STRONG!")
        game.particles:burst(e.x, e.y - 14, phase >= 3 and 30 or 16, Palette.red)
        Camera.knock(phase >= 3 and 4 or 2)
        Sfx.play("spray", 0.8)
    end

    -- Glue clogs the nozzle: whatever it was going to spray is dropped, and the
    -- pressure builds while it is held -- and goes when it is let go.
    if e.frozen > 0 then
        if self.state ~= "enter" and self.state ~= "resting" and self.state ~= "idle" then
            self:calm(e, body)
            self:rest(e, 0.3)
        end
        if not self.clogged and self.state ~= "enter" then
            self.clogged = true
            game:say("CLOGGED!")
        end
        self.clog = min(1, self.clog + dt / def.clog.fill)
    elseif self.clog > 0 then
        self:unclog(game, e, body)
    end

    self.t = self.t - dt
    self.stream = nil
    self[self.state](self, dt, game, e, body)

    self:air(dt, game, e)
    self:pose(dt, e, body)
    body:update(dt)
end

-- What the body shows this frame: swollen with a clog, shaking with a rattle,
-- the nozzle lit while something is about to come out of it.
function DeoBoss:pose(dt, e, body)
    local state = self.state
    body.swell = self.clog
    if state == "shakeTell" then
        body.shake = 1.5
    elseif self.clog > 0 then
        body.shake = self.clog > 0.6 and 1 or 0
    elseif state == "leaking" or state == "leakTell" then
        body.shake = 0.6
    else
        body.shake = 0
    end
    local blink = floor(self.t * 10) % 2 == 0
    body.hot = ((state == "sprayTell" or state == "shakeTell" or state == "fanTell"
        or state == "leakTell" or state == "draughtTell") and blink)
        or state == "spraying" or state == "leaking" or state == "draught"
end

function DeoBoss:calm(e, body)
    self.fan, self.target, self.wind, self.spinning = nil, nil, nil, false
    e.chargePhase = nil
end

function DeoBoss:rest(e, t)
    self.state, self.t = "resting", t
    e.drive = { hold = true }
end

function DeoBoss:resting(dt, game, e, body)
    e.drive = { hold = true }
    body:face(game.player.x - e.x, game.player.y - e.y, 3, dt)
    if self.t <= 0 then
        self.state = "idle"
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.6
    end
end

-- Let go of with its nozzle glued: everything that built up comes out at once,
-- round it, as far out as the swell said.
function DeoBoss:unclog(game, e, body)
    local cl = self.def.clog
    local c = self.cloud
    local r = cl.radius + cl.more * self.clog
    add(c, e.x, e.y, cl.dose, r, 10)
    self.clog, self.clogged = 0, false
    game.particles:burst(e.x, e.y - 12, 30, Palette.blush)
    game.particles:burst(e.x, e.y - 12, 12, Palette.red)
    Camera.knock(4)
    Sfx.play("spray", 0.7)
end

--- the entrance ---------------------------------------------------------------

-- The cap comes off with a click, and it gives the air a test spray straight up:
-- a little mist round it, and the hiss you are going to learn to listen for.
function DeoBoss:enter(dt, game, e, body)
    e.drive = { hold = true }
    body:face(game.player.x - e.x, game.player.y - e.y, math.huge, dt)
    if not self.capped then
        self.capped = true
        Sfx.play("tick", 1.6)
        game.particles:burst(e.x, e.y - 26, 8, Palette.slate)
    end
    if self.t <= 0.5 and not self.tested then
        self.tested = true
        Sfx.play("spray", 1.1)
        add(self.cloud, e.x, e.y, 0.45, 22)
        game.particles:burst(e.x, e.y - 20, 14, Palette.blush)
    end
    if self.t <= 0 then
        self.capped, self.tested = nil, nil
        self.state, self.t = "idle", 0.6
    end
end

--- walking about --------------------------------------------------------------

-- Walking at you, nozzle first, and puffing at you every couple of seconds.
function DeoBoss:idle(dt, game, e, body)
    e.drive = nil
    local p = game.player
    body:face(p.x - e.x, p.y - e.y, 4, dt)
    if e.frozen <= 0 then
        self.spritzT = self.spritzT - dt
        if self.spritzT <= 0 then
            self.spritzT = pick(self.def.spritz.every, self.phase)
            self:spritz(game, e, body, p.x, p.y)
        end
        if self.t <= 0 then self:choose(game, e) end
    end
end

-- One puff, out of the nozzle at a point on the page. It does nothing on the way
-- but leave a little behind it; where it stops it blooms.
function DeoBoss:spritz(game, e, body, tx, ty)
    local s = self.def.spritz
    local nx, ny = body:nozzle(e.x, e.y)
    local dx, dy, dist = util.normalize(tx - nx, ty - ny)
    if dx == 0 and dy == 0 then dx, dy = cos(body.yaw), sin(body.yaw) end
    dist = util.clamp(dist, 20, s.reach)
    self.puffs[#self.puffs + 1] = {
        x = nx, y = ny, dx = dx, dy = dy, left = dist, speed = s.speed,
        size = s.size, dose = s.dose, t = 0,
    }
    Sfx.play("spray", 1.3)
end

-- The full body spray for anywhere; a fan of three spritzes in the first third;
-- the draught from the second, shake well and the leak in the last. The last
-- move is marked down.
function DeoBoss:choose(game, e)
    local def = self.def
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local w = {
        spray = 1.2,
        fan = self.phase == 1 and 1.0 or 0.4,
        draught = self.phase >= def.draught.from and 1.1 or 0,
        shake = self.phase >= def.shake.from and 1.3 or 0,
        leak = self.phase >= def.leak.from and (d < 90 and 1.2 or 0.6) or 0,
    }
    if self.last then w[self.last] = w[self.last] * 0.3 end
    local sum = 0
    for _, v in pairs(w) do sum = sum + v end
    local r = love.math.random() * sum
    local move = "spray"
    for _, k in ipairs({ "spray", "fan", "draught", "shake", "leak" }) do
        r = r - w[k]
        if r <= 0 and w[k] > 0 then move = k break end
    end
    self.last = move
    self[move .. "Start"](self, game, e, e.deodorant)
end

--- the fan of spritzes ----------------------------------------------------------

function DeoBoss:fanStart(game, e, body)
    self.state, self.t = "fanTell", pick(self.def.fan.tell, self.phase)
    e.drive = { hold = true }
    Sfx.play("tick", 1.3)
end

function DeoBoss:fanTell(dt, game, e, body)
    e.drive = { hold = true }
    local p = game.player
    body:face(p.x - e.x, p.y - e.y, 6, dt)
    if self.t > 0 then return end
    local f = self.def.fan
    local nx, ny = body:nozzle(e.x, e.y)
    local at = math.atan2(p.y - ny, p.x - nx)
    local dist = util.clamp(util.len(p.x - nx, p.y - ny), 30, self.def.spritz.reach)
    for k = -1, 1 do
        local a = at + k * f.spread
        self:spritz(game, e, body, nx + cos(a) * dist, ny + sin(a) * dist)
    end
    self:rest(e, pick(f.rest, self.phase))
end

--- the full body spray ----------------------------------------------------------

-- Planted, facing you, the fan it is about to cover dotted on the floor. Which
-- way round it goes is picked now and drawn: the fan is swept from its first
-- edge to its last.
function DeoBoss:sprayStart(game, e, body)
    local s = self.def.spray
    local p = game.player
    local at = math.atan2(p.y - e.y, p.x - e.x)
    local arc = pick(s.arc, self.phase)
    local way = love.math.random() < 0.5 and -1 or 1
    self.fan = { from = at - way * arc / 2, to = at + way * arc / 2, at = at - way * arc / 2,
                 reach = s.reach }
    self.state, self.t = "sprayTell", pick(s.tell, self.phase)
    e.drive = { hold = true }
    Sfx.play("tick", 1.0)
end

function DeoBoss:sprayTell(dt, game, e, body)
    e.drive = { hold = true }
    local fan = self.fan
    body:face(cos(fan.from), sin(fan.from), 8, dt)
    if self.t <= 0 then
        self.state, self.t = "spraying", pick(self.def.spray.time, self.phase)
        self.sprayTime = self.t
        Sfx.play("spray", 0.9)
    end
end

-- The stream: everything along it, out to its reach, sprayed -- thickest near
-- the nozzle and spreading out as it goes, the way a spray does.
function DeoBoss:jet(dt, e, body, reach, rate)
    local c = self.cloud
    local nx, ny = body:nozzle(e.x, e.y)
    local dx, dy = cos(body.yaw), sin(body.yaw)
    for d = 4, reach, 5 do
        local k = 1 - d / (reach + 10)
        add(c, nx + dx * d, ny + dy * d, rate * dt * (0.4 + k), 5 + d * 0.1)
    end
    self.stream = { reach = reach }
end

function DeoBoss:spraying(dt, game, e, body)
    e.drive = { hold = true }
    local fan, s = self.fan, self.def.spray
    local f = 1 - max(0, self.t) / self.sprayTime
    fan.at = fan.from + (fan.to - fan.from) * f
    body:face(cos(fan.at), sin(fan.at), math.huge, dt)
    self:jet(dt, e, body, fan.reach, s.rate)
    self.hissT = (self.hissT or 0) - dt
    if self.hissT <= 0 then
        self.hissT = 0.45
        Sfx.play("spray", 0.95 + f * 0.1)
    end
    if self.t <= 0 then
        self.fan, self.hissT = nil, nil
        self:rest(e, pick(s.rest, self.phase))
    end
end

--- the draught ------------------------------------------------------------------

-- The door is the edge of the box behind it from you: the wind blows from the
-- can's side of the box to yours, along whichever axis you are further apart on.
function DeoBoss:draughtStart(game, e, body)
    local p = game.player
    local dx, dy = p.x - e.x, p.y - e.y
    if abs(dx) >= abs(dy) then dx, dy = dx >= 0 and 1 or -1, 0
    else dx, dy = 0, dy >= 0 and 1 or -1 end
    self.wind = { dx = dx, dy = dy, on = false }
    self.state, self.t = "draughtTell", pick(self.def.draught.tell, self.phase)
    e.drive = { hold = true }
    Sfx.play("transition", 0.7)
end

function DeoBoss:draughtTell(dt, game, e, body)
    e.drive = { hold = true }
    local w = self.wind
    body:face(w.dx, w.dy, 6, dt)
    if self.t <= 0 then
        w.on = true
        self.state, self.t = "draught", pick(self.def.draught.time, self.phase)
        self.puffT = 0
        Camera.knock(2)
        Sfx.play("transition2", 0.6)
    end
end

-- Blowing: the cloud carried, you and the crowd shoved, and the can puffing
-- into it from upwind so there is a plume to walk out of.
function DeoBoss:draught(dt, game, e, body)
    e.drive = { hold = true }
    local w, dr = self.wind, self.def.draught
    body:face(w.dx, w.dy, 6, dt)
    local p = game.player
    p.x, p.y = p.x + w.dx * dr.shove * dt, p.y + w.dy * dr.shove * dt
    if game.arena then p.x, p.y = game.arena:clamp(p.x, p.y, p.radius) end
    for _, o in ipairs(game.enemies) do
        if o ~= e and not o.def.boss and o.frozen <= 0 then
            o.x, o.y = o.x + w.dx * dr.crowd * dt, o.y + w.dy * dr.crowd * dt
        end
    end
    self.puffT = self.puffT - dt
    if self.puffT <= 0 then
        self.puffT = dr.puff
        local nx, ny = body:nozzle(e.x, e.y)
        add(self.cloud, nx + w.dx * 10, ny + w.dy * 10, dr.dose, dr.size)
        Sfx.play("spray", 1.2)
    end
    if self.t <= 0 then
        self.wind = nil
        Sfx.play("stamp", 0.6)
        self:rest(e, pick(dr.rest, self.phase))
    end
end

--- shake well -------------------------------------------------------------------

-- Rattling: the circle follows you for the first part of it, then holds.
function DeoBoss:shakeStart(game, e, body)
    local s = self.def.shake
    self.target = { x = game.player.x, y = game.player.y, r = s.radius, locked = false }
    self.state, self.t = "shakeTell", s.tell
    self.rattleT, self.rattles = 0, 0
    e.drive = { hold = true }
end

function DeoBoss:shakeTell(dt, game, e, body)
    e.drive = { hold = true }
    local s, tg, p = self.def.shake, self.target, game.player
    if self.t > s.tell - s.follow then
        tg.x, tg.y = p.x, p.y
    elseif not tg.locked then
        tg.locked = true
        Sfx.play("tick", 0.8)
    end
    body:face(tg.x - e.x, tg.y - e.y, 6, dt)
    -- The ball inside, clacking: quicker as it goes.
    self.rattleT = self.rattleT - dt
    if self.rattleT <= 0 then
        self.rattles = self.rattles + 1
        self.rattleT = 0.06 + 0.1 * max(0, self.t) / s.tell
        Sfx.play("tick", self.rattles % 2 == 0 and 1.9 or 1.6)
    end
    if self.t > 0 then return end
    -- Emptied into the circle.
    add(self.cloud, tg.x, tg.y, s.dose, tg.r, 10)
    local nx, ny = body:nozzle(e.x, e.y)
    self.blast = { x0 = nx, y0 = ny, x1 = tg.x, y1 = tg.y, t = 0 }
    game.particles:burst(tg.x, tg.y, 30, Palette.blush)
    game.particles:burst(tg.x, tg.y, 14, Palette.red)
    Camera.knock(5)
    Sfx.play("spray", 0.6)
    Sfx.play("stamp", 0.7)
    self.target = nil
    self:rest(e, pick(s.rest, self.phase))
end

--- the leak -------------------------------------------------------------------

function DeoBoss:leakStart(game, e, body)
    self.state, self.t = "leakTell", self.def.leak.tell
    e.drive = { hold = true }
    Sfx.play("stamp", 1.3)
    game.particles:burst(e.x, e.y - 10, 10, Palette.slate)
end

function DeoBoss:leakTell(dt, game, e, body)
    e.drive = { hold = true }
    self.spinning = true
    if self.t <= 0 then
        self.state, self.t = "leaking", self.def.leak.time
        self.hissT = 0
    end
end

-- Spinning on its own jet, and pushed about the box by it: it goes the way the
-- nozzle is not pointing, so it wanders in loops rather than coming at you.
function DeoBoss:leaking(dt, game, e, body)
    local l = self.def.leak
    body:spin(l.spin * dt)
    local dx, dy = cos(body.yaw), sin(body.yaw)
    self:jet(dt, e, body, l.reach, l.rate)
    e.drive = { dash = true, dx = -dx, dy = -dy, speed = l.speed }
    self.hissT = self.hissT - dt
    if self.hissT <= 0 then
        self.hissT = 0.4
        Sfx.play("spray", 1.4)
    end
    if self.t <= 0 then
        self.spinning, self.hissT = false, nil
        self:rest(e, pick(l.rest, self.phase))
    end
end

--- the air --------------------------------------------------------------------

-- Everything that is not the can: the puffs in flight, the cloud moving on, and
-- what being in it does to you.
function DeoBoss:air(dt, game, e)
    local def, c, p = self.def, self.cloud, game.player
    local cl = def.cloud

    for i = #self.puffs, 1, -1 do
        local f = self.puffs[i]
        local step = min(f.left, f.speed * dt)
        f.x, f.y = f.x + f.dx * step, f.y + f.dy * step
        f.left, f.t = f.left - step, f.t + dt
        add(c, f.x, f.y, 1.2 * dt, 6)
        if f.left <= 0 then
            add(c, f.x, f.y, f.dose, f.size)
            game.particles:burst(f.x, f.y, 5, Palette.blush)
            table.remove(self.puffs, i)
        end
    end

    -- You, wading: what is in front of you is pushed aside, as hard as you are
    -- walking.
    if self.lastPX then
        local moved = util.len(p.x - self.lastPX, p.y - self.lastPY)
        local pace = min(1, moved / max(1e-6, 58 * dt))
        if c.any and pace > 0.1 then part(c, p.x, p.y, cl.part, pace * cl.wade * dt) end
    end
    self.lastPX, self.lastPY = p.x, p.y

    local w = self.wind
    local wx, wy = 0, 0
    if w and w.on then wx, wy = w.dx * def.draught.speed, w.dy * def.draught.speed end
    if c.any then
        local left = dt
        while left > 0 do
            local h = min(STEP, left)
            stepCloud(c, h, cl.spread, pick(cl.life, self.phase), wx, wy)
            left = left - h
        end
    end

    -- What it does to you: thin, you cough and slow down; thick, it hurts.
    local here = c.any and sample(c, p.x, p.y) or 0
    if here > cl.thin then
        p.drag = 1 - cl.drag * min(1, (here - cl.thin) / (cl.thick - cl.thin))
        self.coughT = self.coughT - dt
        if self.coughT <= 0 then
            self.coughT = 0.35
            game.particles:burst(p.x, p.y - 6, 1, here >= cl.thick and Palette.red or Palette.blush)
        end
    else
        p.drag = nil
    end
    self.chokeT = max(0, self.chokeT - dt)
    if here >= cl.thick and self.chokeT <= 0 then
        self.chokeT = cl.every
        if p:hurt(scaled(e, cl.damage)) then
            game.particles:burst(p.x, p.y, 6, Palette.red)
        end
    end

    -- The draught's streaks, coming in across the page.
    if w then
        local vx, vy, vw, vh = Camera.bounds()
        local rate = w.on and 40 or 12
        local n = floor(rate * dt + love.math.random())
        for _ = 1, n do
            local sx, sy
            if w.dx ~= 0 then
                sx = w.dx > 0 and vx - 10 or vx + vw + 10
                sy = vy + love.math.random() * vh
            else
                sx = vx + love.math.random() * vw
                sy = w.dy > 0 and vy - 10 or vy + vh + 10
            end
            self.streaks[#self.streaks + 1] = { x = sx, y = sy, len = 6 + love.math.random() * 10,
                                                speed = (w.on and 300 or 160) * (0.7 + love.math.random() * 0.6),
                                                dx = w.dx, dy = w.dy, t = 0 }
        end
    end
    for i = #self.streaks, 1, -1 do
        local s = self.streaks[i]
        s.t = s.t + dt
        s.x, s.y = s.x + s.dx * s.speed * dt, s.y + s.dy * s.speed * dt
        if s.t >= STREAK_LIFE then table.remove(self.streaks, i) end
    end

    if self.blast then
        self.blast.t = self.blast.t + dt
        if self.blast.t > 0.25 then self.blast = nil end
    end
end

--- going down -----------------------------------------------------------------

-- Empty: the cloud goes with it, and you can breathe again. Called by
-- Game:killEnemy.
function DeoBoss:dropParts(game)
    local e = self.e
    if self.cloud then
        for i = 1, #self.cloud.d do self.cloud.d[i] = 0 end
        self.cloud.any = false
    end
    self.puffs, self.streaks, self.wind, self.fan, self.target = {}, {}, nil, nil, nil
    game.player.drag = nil
    if e then game.particles:burst(e.x, e.y - 12, 30, Palette.blush) end
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

-- A dotted arc of radius r round (x, y), from angle a0 to a1.
local function arc(x, y, r, a0, a1, every)
    if a1 < a0 then a0, a1 = a1, a0 end
    local n = max(4, floor((a1 - a0) * r / (every or 3)))
    for k = 0, n do
        local a = a0 + (a1 - a0) * k / n
        love.graphics.rectangle("fill", floor(x + cos(a) * r), floor(y + sin(a) * r), 1, 1)
    end
end

-- The cloud, on the page: a dot here and there where it is thin, more where it
-- is thick, and red where it hurts. Dots rather than a fill because there is no
-- alpha in this book -- the page shows through the gaps, which is what makes it
-- mist rather than paint -- and they are picked afresh a few times a second off
-- a hash, so it boils gently instead of sitting still.
function DeoBoss:drawCloud(time)
    local c = self.cloud
    if not c or not c.any then return end
    local cl = self.def.cloud
    local vx, vy, vw, vh = Camera.bounds()
    local x0 = max(c.left, floor(vx / 2) * 2)
    local x1 = min(c.left + c.w, vx + vw)
    local y0 = max(c.top, floor(vy / 2) * 2)
    local y1 = min(c.top + c.h, vy + vh)
    local boil = floor(time * 5)
    local d, cols = c.d, c.cols
    local thick, thin = cl.thick, cl.thin * 0.5
    local red, blush = {}, {}
    -- Skipped a cell at a time where the cell and its neighbours are clean air.
    for cy = y0, y1, CELL do
        local r = floor((cy - c.top) / CELL) + 1
        for cx = x0, x1, CELL do
            local col = floor((cx - c.left) / CELL) + 1
            local hot = false
            for rr = max(1, r - 1), min(c.rows, r + 1) do
                for cc = max(1, col - 1), min(cols, col + 1) do
                    if d[(rr - 1) * cols + cc] > CLEAN * 4 then hot = true end
                end
            end
            if hot then
                for py = cy, min(cy + CELL - 1, y1), 2 do
                    for px = cx, min(cx + CELL - 1, x1), 2 do
                        local v = sample(c, px, py)
                        if v > thin then
                            local h = util.hash01(px, py, boil)
                            local cover = min(0.6, v * 0.42)
                            if h < cover then
                                local ox = h * 7 % 2 < 1 and 0 or 1
                                if v >= thick and h < cover * 0.7 then
                                    red[#red + 1] = px + ox
                                    red[#red + 1] = py
                                else
                                    blush[#blush + 1] = px + ox
                                    blush[#blush + 1] = py
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    love.graphics.setColor(Palette.blush)
    for i = 1, #blush, 2 do love.graphics.rectangle("fill", blush[i], blush[i + 1], 1, 1) end
    love.graphics.setColor(Palette.red)
    for i = 1, #red, 2 do love.graphics.rectangle("fill", red[i], red[i + 1], 1, 1) end
end

-- On the floor: the cloud, the fan a spray is about to cover, the circle shake
-- well is going to empty into, and the reach of a leak.
function DeoBoss:drawGround(time)
    local e = self.e
    if not e then return end
    self:drawCloud(time)

    local fan = self.fan
    if fan then
        local blink = floor(time * 8) % 2 == 0
        love.graphics.setColor(self.state == "sprayTell" and blink and Palette.red or Palette.blush)
        arc(e.x, e.y, fan.reach, fan.from, fan.to, 3)
        for _, a in ipairs({ fan.from, fan.to }) do
            dashes(e.x + cos(a) * 14, e.y + sin(a) * 14, cos(a), sin(a), fan.reach - 14, time * 30, 3)
        end
        -- Which way it is going to go round: an arrow at the first edge.
        if self.state == "sprayTell" then
            local a = fan.from
            local way = fan.to > fan.from and 1 or -1
            local r = fan.reach * 0.6
            local tx, ty = e.x + cos(a) * r, e.y + sin(a) * r
            local hx, hy = -sin(a) * way, cos(a) * way
            love.graphics.setColor(Palette.red)
            pixelart.line(floor(tx), floor(ty), floor(tx + hx * 8), floor(ty + hy * 8))
        end
    end

    local tg = self.target
    if tg then
        local blink = floor(time * (tg.locked and 14 or 6)) % 2 == 0
        love.graphics.setColor(blink and Palette.red or Palette.blush)
        pixelart.circleOutline(floor(tg.x), floor(tg.y), tg.r)
        if tg.locked then pixelart.circleOutline(floor(tg.x), floor(tg.y), tg.r + 1) end
        love.graphics.setColor(Palette.blush)
        arc(tg.x, tg.y, tg.r - 3, 0, TAU, 4)
    end

    -- Solid rather than dotted, both of these: they are drawn over the mist,
    -- and a dotted ring in a cloud of dots is a ring you cannot find.
    if self.spinning then
        love.graphics.setColor(floor(time * 10) % 2 == 0 and Palette.red or Palette.blush)
        pixelart.circleOutline(floor(e.x), floor(e.y), self.def.leak.reach)
    end

    -- The draught's door, while it is counted in: the edge it comes from, dashed.
    local w = self.wind
    local box = self.box
    if w and not w.on and box then
        love.graphics.setColor(floor(time * 8) % 2 == 0 and Palette.sky or Palette.blue)
        if w.dx ~= 0 then
            local x = w.dx > 0 and box.left + 3 or box:right() - 3
            dashes(x, box.top, 0, 1, box.h, time * 40, 4)
        else
            local y = w.dy > 0 and box.top + 3 or box:bottom() - 3
            dashes(box.left, y, 1, 0, box.w, time * 40, 4)
        end
    end
end

-- Over the crowd: the stream coming out of it, the puffs in flight, the burst,
-- and the draught's streaks.
function DeoBoss:drawAir(time, e)
    if e and e.deodorant and self.stream then
        local body = e.deodorant
        local nx, ny, sx, sy = body:nozzle(e.x, e.y)
        local lift = ny - sy
        local dx, dy = cos(body.yaw), sin(body.yaw)
        local reach = self.stream.reach
        local tick = floor(time * 20)
        -- The jet: a solid line out of the nozzle, falling to the floor as it
        -- goes, red where it is thickest -- and round it the droplets, paper and
        -- blush, spreading. The line is what tells it from the mist it lays.
        local lx, ly
        for d = 1, reach do
            local k = d / reach
            local x = floor(nx + dx * d)
            local y = floor(ny + dy * d - lift * (1 - k) ^ 2)
            if x ~= lx or y ~= ly then
                if k < 0.55 or util.hash01(d, 1, tick) < 1.4 - k * 1.5 then
                    love.graphics.setColor(k < 0.35 and Palette.red or Palette.blush)
                    love.graphics.rectangle("fill", x, y, 1, 1)
                end
                lx, ly = x, y
            end
        end
        for d = 3, reach, 2 do
            local k = d / reach
            local spread = 1 + d * 0.14
            for n = 1, 2 do
                local h = util.hash01(d, n, tick)
                if h < 0.8 - k * 0.4 then
                    local side = (util.hash01(n, d, tick + 7) - 0.5) * 2 * spread
                    local x = nx + dx * d - dy * side
                    local y = ny + dy * d + dx * side - lift * (1 - k) ^ 2
                    love.graphics.setColor(h < 0.35 and Palette.paper or Palette.blush)
                    love.graphics.rectangle("fill", floor(x), floor(y), 1, 1)
                end
            end
        end
    end

    for _, f in ipairs(self.puffs) do
        local x, y = floor(f.x), floor(f.y - 6)
        local r = 2 + min(3, f.t * 8)
        for k = 0, 9 do
            local a = k / 10 * TAU + time * 3
            local h = util.hash01(k, floor(time * 12), 3)
            love.graphics.setColor(h < 0.5 and Palette.blush or Palette.paper)
            love.graphics.rectangle("fill", floor(x + cos(a) * r * h), floor(y + sin(a) * r * h), 1, 1)
        end
        love.graphics.setColor(Palette.red)
        love.graphics.rectangle("fill", x, y, 1, 1)
    end

    local b = self.blast
    if b then
        love.graphics.setColor(Palette.blush)
        local dx, dy, dist = util.normalize(b.x1 - b.x0, b.y1 - b.y0)
        dashes(b.x0, b.y0, dx, dy, dist, time * 60, 2)
    end

    if #self.streaks > 0 then
        love.graphics.setColor(Palette.graphite)
        for _, s in ipairs(self.streaks) do
            dashes(s.x, s.y, s.dx, s.dy, s.len, 0, 8)
        end
    end
end

return DeoBoss
