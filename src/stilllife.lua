-- The ART boss's mind: a still life, and the fight in the book about *light*.
--
-- The eye is a fight about the ground, the whistle the air, the metronome
-- time, the stamp which box you are in, the dictionary lines and the die
-- reading a number. This one is about where the light is. ART is the page
-- with nothing ruled on it, and the first thing an art class puts on a blank
-- page is a cube, a sphere and a cone under a lamp -- so that is what walks
-- into the box at the end of it. It does not walk, being a still life. It holds
-- still and the lamp goes round it.
--
-- **The lamp** is always on the page, drifting round the group, and the body
-- is lit from wherever it is (src/plaster.lua): the side of every solid that
-- faces it is the paper, the side that turns away is slate. Each solid throws
-- its shadow across the floor directly away from it. Most of the time those are
-- short smudges, and what they are for is teaching you to read the light.
--
-- **The shade** is the move that cashes that in. The lamp swings round to the
-- far side of the group from you and the three shadows grow out across the
-- box, hatched while they are counted in, then filled -- and a filled shadow
-- hurts. Each solid throws its own, fanned out from the lamp, so there are
-- gaps of light between them as well as round them. From the middle third the
-- lamp keeps moving while they are filled, so the shadows sweep and you walk
-- with them; in the last third there are two lamps, and two fans.
--
-- **The cube** leaves the group: up off the table and out of sight, its shadow
-- coming down on where you were standing, then down onto it -- and it sits
-- there, a block in the way, before it hops home.
--
-- **The sphere** (from the middle third) is bowled: a line drawn from it to
-- you, a shudder, and it rolls down the line to the edge of the box and back.
--
-- **The cone** (in the last third) turns over and spins on its point like a
-- top, wandering after you and throwing chips of plaster off in a spiral,
-- until it falls over and is put back.
--
-- **Glue holds the table.** A glued still life cannot move its lamp, so a
-- shade it was counting in is dropped, and it cannot be lifted to somewhere
-- nearer you. What is already off the table goes on doing what it was doing:
-- glue holds the group, not a cube in the air.
--
-- The body is src/plaster.lua, painted every frame; this file only moves the
-- lamp, takes pieces off the table and puts them back, and reads them.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local Plaster = require("src.plaster")
local pixelart = require("src.pixelart")
local util = require("src.util")

local StillLife = {}
StillLife.__index = StillLife

local TAU = math.pi * 2
local floor = math.floor

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new).
local function scaled(e, damage) return damage * e.damage / e.def.damage end

-- The shortest way round from angle a to angle b.
local function wrap(a)
    return (a + math.pi) % TAU - math.pi
end

-- Where the group's pieces stand round its floor point, which is drawn
-- `FOOT` under the boss's own middle so the bulk of the group is over its
-- hitbox: the cube front left, the sphere front right, the cone behind them.
-- The order is the one `pieces` is built in and every index below reads.
local FOOT = 8
local CUBE, SPHERE, CONE = 1, 2, 3

function StillLife.body()
    return Plaster.new({
        Plaster.cube(-11, 2, 7),
        Plaster.sphere(11, 4, 8),
        Plaster.cone(0, -9, 7, 22),
    }, FOOT)
end

function StillLife.new(def)
    return setmetatable({
        def = def.still,
        phase = 1,
        -- It walks on resting: the first thing the player should see it do is
        -- nothing, with the lamp going round it.
        state = "rest", t = 1.6,
        last = nil,
        lamps = nil,
        loose = nil,      -- the piece that is off the table, if one is
        e = nil,
    }, StillLife)
end

function StillLife:busy()
    return self.state ~= "rest"
end

--- the loop -------------------------------------------------------------------

function StillLife:update(dt, game, e)
    self.e, self.box = e, game.arena
    if dt <= 0 then return end
    local body = e.plaster
    if not self.lamps then
        local p = game.player
        local a = math.atan2(p.y - e.y, p.x - e.x) + math.pi * 0.75
        self.lamps = { { a = a } }
        self:placeLamps(e)
    end
    if self.shockT then self.shockT = math.max(0, self.shockT - dt) end

    -- The phase, at the eye's thirds: another piece joins in, and the lamp
    -- learns something. Whatever it was in the middle of is put back.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        self:clear(game, e)
        self.state, self.t = "change", 0.9
        game.particles:burst(e.x, e.y, phase >= 3 and 24 or 14, Palette.red)
        Camera.knock(2)
        Sfx.play("pin", 0.7)
        if phase >= 3 then
            local a = self.lamps[1].a + math.pi
            self.lamps[2] = { a = a }
            game:say("ANOTHER LAMP!")
        else
            game:say("THE LAMP MOVES!")
        end
    end

    e.drive = { hold = true }

    -- Stuck to the page: the lamp is stuck with it. A shade still being counted
    -- in is dropped and a lift to somewhere else is put down where it is; what
    -- is off the table already carries on.
    if e.frozen > 0 then
        if self.state == "shade" and self.sub == "tell" then
            self.state, self.t, self.wedges = "rest", pick(self.def.cool, self.phase), nil
        elseif self.state == "move" then
            e.hop = 0
            self.state, self.t = "rest", pick(self.def.cool, self.phase)
        end
        e.blowT = 0
        if self.state == "rest" or self.state == "change" then
            self:light(e, body)
            return
        end
    end

    self.t = self.t - dt
    if self.state ~= "shade" and self.state ~= "change" then self:drift(dt) end
    self[self.state](self, dt, game, e, body)
    self:placeLamps(e)
    self:light(e, body)
end

-- Every piece back on the table and every move dropped: the change of phase.
function StillLife:clear(game, e)
    local body = e.plaster
    if self.loose then
        game.particles:burst(self.loose.x, self.loose.y, 8, Palette.graphite)
        self:home(e, body)
    end
    self.wedges, self.mark, self.aim = nil, nil, nil
    e.blowT, e.hop = 0, 0
end

-- The idle drift: the lamp going slowly round, so the light on the body is
-- always moving and always readable.
function StillLife:drift(dt)
    local dir = self.phase == 2 and -1 or 1
    for k, l in ipairs(self.lamps) do
        l.a = l.a + self.def.lamp.drift * dt * (k == 1 and dir or -dir)
    end
end

-- The lamps' places on the page, off their angles round the group: a ring
-- `ring` out, pulled inside the box when the ring would leave it.
function StillLife:placeLamps(e)
    local ring = self.def.lamp.ring
    for _, l in ipairs(self.lamps) do
        local x, y = e.x + math.cos(l.a) * ring, e.y + FOOT + math.sin(l.a) * ring
        if self.box then x, y = self.box:clamp(x, y, 8) end
        l.x, l.y = x, y
    end
end

-- The body lit from the first lamp, and whatever is off the table lit from the
-- same lamp where it is.
function StillLife:light(e, body)
    local l = self.lamps[1]
    local high = self.def.lamp.high
    body.lamp[1], body.lamp[2], body.lamp[3] = l.x - e.x, l.y - (e.y + FOOT), high
    local loose = self.loose
    if loose then
        loose.painter.lamp[1] = l.x - loose.x
        loose.painter.lamp[2] = l.y - loose.y
        loose.painter.lamp[3] = high
    end
end

-- Resting between moves, and then picking the next: never the same one twice
-- running, so a phase with two moves in it alternates.
function StillLife:rest(dt, game, e)
    if self.t > 0 then return end
    local p = game.player
    local dist = util.len(p.x - e.x, p.y - e.y)
    local mv = self.def.move
    if dist > mv.far and self.state ~= "move" and self.last ~= "move" then
        local dx, dy = (p.x - e.x) / dist, (p.y - e.y) / dist
        local go = math.min(mv.reach, dist - mv.near)
        local tx, ty = e.x + dx * go, e.y + dy * go
        if self.box then tx, ty = self.box:clamp(tx, ty, e.radius + 8) end
        self.from = { x = e.x, y = e.y }
        self.to = { x = tx, y = ty }
        self.state, self.t, self.last = "move", mv.time, "move"
        return
    end
    local moves = self.def.moves[self.phase]
    local choice
    repeat
        choice = moves[love.math.random(#moves)]
    until #moves == 1 or choice ~= self.last
    self.last = choice
    self["start_" .. choice](self, game, e, e.plaster)
end

-- The whole group lifted and set down nearer you: how a thing that never walks
-- keeps up. A hop rather than a slide, so it is the table being rearranged and
-- not the table creeping.
function StillLife:move(dt, game, e)
    local mv = self.def.move
    local f = 1 - math.max(0, self.t) / mv.time
    e.x = self.from.x + (self.to.x - self.from.x) * f
    e.y = self.from.y + (self.to.y - self.from.y) * f
    e.hop = floor(math.sin(math.pi * f) * mv.high + 0.5)
    if self.t <= 0 then
        e.hop = 0
        Sfx.play("tick", 0.8)
        Camera.knock(1)
        game.particles:burst(e.x, e.y + FOOT, 6, Palette.graphite)
        self.state, self.t = "rest", 0.5
    end
end

function StillLife:change(dt, game, e)
    if self.t <= 0 then self.state, self.t = "rest", 0.6 end
end

--- shadows --------------------------------------------------------------------

-- Where a piece of the group is on the page, and how wide it is to a lamp.
local function spot(e, p)
    local x, y = Plaster.centre(p)
    if p.kind == "cone" then x, y = p.apex[1], p.apex[2] end
    return e.x + x, e.y + FOOT + y
end

local function width(p)
    if p.kind == "cube" then return p.half * 1.2 end
    return p.r
end

-- A shadow: the wedge a lamp at (lx, ly) throws past something `r` wide at
-- (px, py), from the thing out to `len` beyond it. Kept as the angles it is
-- made of, which is what the hit test reads, and the four corners the drawing
-- fills.
local function wedge(lx, ly, px, py, r, len)
    local dx, dy = px - lx, py - ly
    local d = math.max(r + 1, util.len(dx, dy))
    local a = math.atan2(dy, dx)
    local b = math.asin(math.min(0.9, r / d))
    local near, far = d, d + len
    return {
        lx = lx, ly = ly, a = a, b = b, near = near, far = far,
        poly = {
            lx + math.cos(a - b) * near, ly + math.sin(a - b) * near,
            lx + math.cos(a - b) * far, ly + math.sin(a - b) * far,
            lx + math.cos(a + b) * far, ly + math.sin(a + b) * far,
            lx + math.cos(a + b) * near, ly + math.sin(a + b) * near,
        },
    }
end

-- Whether a body `pr` round at (x, y) is in a shadow: beyond the thing that
-- threw it, and inside its angle by more than its own width.
local function inWedge(w, x, y, pr)
    local dx, dy = x - w.lx, y - w.ly
    local d = util.len(dx, dy)
    if d < w.near or d > w.far then return false end
    return math.abs(wrap(math.atan2(dy, dx) - w.a)) <= w.b + pr / d
end

-- Every shadow on the page this frame, at `len`: one per lamp per piece on the
-- table.
function StillLife:shadows(e, len)
    local out = {}
    for _, l in ipairs(self.lamps) do
        for _, p in ipairs(e.plaster.pieces) do
            if not p.hidden then
                local x, y = spot(e, p)
                out[#out + 1] = wedge(l.x, l.y, x, y, width(p), len)
            end
        end
    end
    return out
end

--- the shade ------------------------------------------------------------------

-- The lamp swings to the far side of the group from you, give or take, and
-- the second lamp (last third) to somewhere else round it.
function StillLife:start_shade(game, e)
    local sh = self.def.shade
    local p = game.player
    local away = math.atan2(p.y - e.y, p.x - e.x) + math.pi
    local turn = (love.math.random() * 2 - 1) * sh.spread
    self.lamps[1].to = away + turn
    if self.lamps[2] then
        self.lamps[2].to = away + turn + (love.math.random() < 0.5 and -1 or 1) * sh.apart
    end
    for _, l in ipairs(self.lamps) do
        l.from = l.a
        l.to = l.a + wrap(l.to - l.a)
    end
    self.swing = pick(sh.swing, self.phase) * (love.math.random() < 0.5 and -1 or 1)
    self.state, self.sub, self.t = "shade", "tell", pick(sh.tell, self.phase)
    self.len = sh.short
    Sfx.play("tick", 0.7)
end

function StillLife:shade(dt, game, e)
    local sh = self.def.shade
    if self.sub == "tell" then
        local total = pick(sh.tell, self.phase)
        local f = math.min(1, (1 - math.max(0, self.t) / total) / 0.6)
        local ease = f * f * (3 - 2 * f)
        for _, l in ipairs(self.lamps) do l.a = l.from + (l.to - l.from) * ease end
        self.len = sh.short + (sh.length - sh.short) * ease
        if self.t <= 0 then
            self.sub, self.t = "hot", pick(sh.hot, self.phase)
            self.len = sh.length
            Camera.knock(2)
            Sfx.play("pin", 0.8)
        end
    elseif self.sub == "hot" then
        local hot = pick(sh.hot, self.phase)
        for _, l in ipairs(self.lamps) do l.a = l.a + self.swing / hot * dt end
        self:placeLamps(e)
        local p = game.player
        for _, w in ipairs(self:shadows(e, sh.length)) do
            if inWedge(w, p.x, p.y, p.radius) then
                if p:hurt(scaled(e, sh.damage)) then
                    game.particles:burst(p.x, p.y, 6, Palette.red)
                end
                break
            end
        end
        if self.t <= 0 then self.sub, self.t = "fade", sh.fade end
    else
        self.len = sh.short + (sh.length - sh.short) * math.max(0, self.t) / sh.fade
        if self.t <= 0 then
            self.len = nil
            self.state, self.t = "rest", pick(self.def.cool, self.phase)
        end
    end
end

--- off the table --------------------------------------------------------------

-- A piece taken off the table into a painter of its own, drawn where it is on
-- the page rather than where it stood in the group.
function StillLife:lift(e, body, k, piece)
    local x, y = spot(e, body.pieces[k])
    body.pieces[k].hidden = true
    body:touch()
    self.loose = { k = k, x = x, y = y, piece = piece, painter = Plaster.new({ piece }, 0) }
    return self.loose
end

-- And put back: the piece is shown in the group again, turned the way it came
-- back (a cube) or stood up again (the cone and sphere have no way round).
function StillLife:home(e, body)
    local loose = self.loose
    if not loose then return end
    local p = body.pieces[loose.k]
    if p.kind == "cube" then
        local q = loose.piece
        for i = 1, 3 do p.ax[i], p.ay[i], p.az[i] = q.ax[i], q.ay[i], q.az[i] end
        -- Put down flat: whichever way it is turned, set square on the floor
        -- about the upright, so a cube is never left balanced on an edge.
        local yaw = math.atan2(q.ax[2], q.ax[1])
        p.ax[1], p.ax[2], p.ax[3] = math.cos(yaw), math.sin(yaw), 0
        p.ay[1], p.ay[2], p.ay[3] = -math.sin(yaw), math.cos(yaw), 0
        p.az[1], p.az[2], p.az[3] = 0, 0, 1
    end
    p.hidden = false
    body:touch()
    self.loose = nil
end

-- Where a piece's home spot in the group is on the page.
function StillLife:homeSpot(e, k)
    return spot(e, e.plaster.pieces[k])
end

-- Hurt you if you are within `r` of where a loose piece is on the floor.
local function bump(game, e, x, y, r, damage)
    local p = game.player
    if util.len(p.x - x, p.y - y) < r + p.radius and p:hurt(scaled(e, damage)) then
        game.particles:burst(p.x, p.y, 6, Palette.red)
    end
end

--- the cube -------------------------------------------------------------------

function StillLife:start_drop(game, e, body)
    local dr = self.def.drop
    local cube = Plaster.cube(0, 0, body.pieces[CUBE].half)
    local src = body.pieces[CUBE]
    for i = 1, 3 do cube.ax[i], cube.ay[i], cube.az[i] = src.ax[i], src.ay[i], src.az[i] end
    self:lift(e, body, CUBE, cube)
    self.state, self.sub, self.t = "drop", "up", dr.up
    Sfx.play("tick", 0.6)
end

function StillLife:drop(dt, game, e, body)
    local dr = self.def.drop
    local loose = self.loose
    local cube = loose.piece
    if self.sub == "up" then
        local f = 1 - math.max(0, self.t) / dr.up
        cube.lift = dr.high * f * f
        Plaster.turn(cube, 1, 0.4, 0, dt * 12)
        loose.painter:touch()
        if self.t <= 0 then
            local p = game.player
            local x, y = p.x, p.y
            if self.box then x, y = self.box:clamp(x, y, cube.half + 4) end
            self.mark = { x = x, y = y }
            loose.painter.hidden = true
            self.sub, self.t = "aim", dr.aim
        end
    elseif self.sub == "aim" then
        if self.t <= 0 then
            loose.x, loose.y = self.mark.x, self.mark.y
            loose.painter.hidden = false
            self.sub, self.t = "down", dr.down
        end
    elseif self.sub == "down" then
        local f = math.max(0, self.t) / dr.down
        cube.lift = dr.high * f * f
        Plaster.turn(cube, 0.3, 1, 0, dt * 12)
        loose.painter:touch()
        if self.t <= 0 then
            cube.lift = 0
            -- Square on the floor, as it would land: anything else balances a
            -- cube on an edge for as long as it sits there.
            local yaw = math.atan2(cube.ax[2], cube.ax[1])
            cube.ax[1], cube.ax[2], cube.ax[3] = math.cos(yaw), math.sin(yaw), 0
            cube.ay[1], cube.ay[2], cube.ay[3] = -math.sin(yaw), math.cos(yaw), 0
            cube.az[1], cube.az[2], cube.az[3] = 0, 0, 1
            loose.painter:touch()
            self.mark = nil
            bump(game, e, loose.x, loose.y, dr.shock, dr.damage)
            self.shockAt, self.shockT = { x = loose.x, y = loose.y }, 0.3
            Camera.knock(4)
            Sfx.play("pin", 0.5)
            game.particles:burst(loose.x, loose.y, 18, Palette.red)
            for _ = 1, 8 do
                game.particles:crumb(loose.x, loose.y, nil, nil, cube.half, Palette.graphite)
            end
            self.sub, self.t = "sit", dr.sit
        end
    elseif self.sub == "sit" then
        bump(game, e, loose.x, loose.y, cube.half + 2, dr.damage)
        if self.t <= 0 then
            self.from = { x = loose.x, y = loose.y }
            self.sub, self.t = "back", dr.back
        end
    else
        local hx, hy = self:homeSpot(e, CUBE)
        local f = 1 - math.max(0, self.t) / dr.back
        loose.x = self.from.x + (hx - self.from.x) * f
        loose.y = self.from.y + (hy - self.from.y) * f
        cube.lift = math.sin(math.pi * f) * dr.hop
        Plaster.turn(cube, hy - self.from.y, self.from.x - hx, 0, dt * 6)
        loose.painter:touch()
        if self.t <= 0 then
            self:home(e, body)
            Sfx.play("tick", 0.9)
            self.state, self.t = "rest", pick(self.def.cool, self.phase)
        end
    end
end

--- the sphere -----------------------------------------------------------------

-- How far a line along (dx, dy) from (x, y) goes before the box stops it,
-- `pad` short of the edge.
local function reach(box, x, y, dx, dy, most, pad)
    local t = most
    if box then
        if dx > 1e-6 then t = math.min(t, (box:right() - pad - x) / dx) end
        if dx < -1e-6 then t = math.min(t, (box.left + pad - x) / dx) end
        if dy > 1e-6 then t = math.min(t, (box:bottom() - pad - y) / dy) end
        if dy < -1e-6 then t = math.min(t, (box.top + pad - y) / dy) end
    end
    return math.max(0, t)
end

function StillLife:start_roll(game, e, body)
    local rl = self.def.roll
    local p = game.player
    local x, y = self:homeSpot(e, SPHERE)
    local dx, dy = util.normalize(p.x - x, p.y - y)
    if dx == 0 and dy == 0 then dx = 1 end
    self.aim = { x = x, y = y, dx = dx, dy = dy,
                 len = reach(self.box, x, y, dx, dy, rl.length, body.pieces[SPHERE].r + 2) }
    self.state, self.sub, self.t = "roll", "wind", rl.wind
end

function StillLife:roll(dt, game, e, body)
    local rl = self.def.roll
    if self.sub == "wind" then
        e.blowT = math.max(0, self.t)
        if self.t <= 0 then
            e.blowT = 0
            local ball = Plaster.sphere(0, 0, body.pieces[SPHERE].r)
            self:lift(e, body, SPHERE, ball)
            self.gone = 0
            self.sub = "out"
            Sfx.play("tick", 0.8)
        end
        return
    end
    local loose = self.loose
    local a = self.aim
    local r = loose.piece.r
    if self.sub == "out" then
        self.gone = math.min(a.len, self.gone + rl.speed * dt)
        loose.x, loose.y = a.x + a.dx * self.gone, a.y + a.dy * self.gone
        if self.gone >= a.len then
            self.sub = "back"
            Camera.knock(2)
            Sfx.play("tick", 1.0)
            game.particles:burst(loose.x, loose.y, 6, Palette.graphite)
        end
    else
        local hx, hy = self:homeSpot(e, SPHERE)
        local dx, dy, d = util.normalize(hx - loose.x, hy - loose.y)
        local step = rl.speed * rl.back * dt
        if d <= step then
            self:home(e, body)
            self.aim = nil
            Sfx.play("tick", 0.9)
            self.state, self.t = "rest", pick(self.def.cool, self.phase)
            return
        end
        loose.x, loose.y = loose.x + dx * step, loose.y + dy * step
    end
    if love.math.random() < dt * 20 then
        game.particles:crumb(loose.x, loose.y + r, nil, nil, 2, Palette.graphite)
    end
    bump(game, e, loose.x, loose.y, r, rl.damage)
end

--- the cone -------------------------------------------------------------------

-- The cone's axis off two angles: `phi` from straight up (0 is apex down,
-- standing on its point; pi is apex up, standing on its base) and `psi` round
-- the upright. Apex to base, as the painter wants it.
local function setAxis(cone, phi, psi)
    local s = math.sin(phi)
    cone.axis[1], cone.axis[2], cone.axis[3] = s * math.cos(psi), s * math.sin(psi), math.cos(phi)
end

function StillLife:start_top(game, e, body)
    local src = body.pieces[CONE]
    local cone = Plaster.cone(0, 0, src.r, src.h)
    self:lift(e, body, CONE, cone)
    self.phi, self.psi = math.pi, 0
    self.spray, self.chipT = love.math.random() * TAU, 0
    self.state, self.sub, self.t = "top", "flip", self.def.top.flip
    Sfx.play("tick", 0.7)
end

function StillLife:top(dt, game, e, body)
    local tp = self.def.top
    local loose = self.loose
    local cone = loose.piece
    local lying = math.pi / 2 - math.atan(cone.r / cone.h)
    if self.sub == "flip" then
        -- Over in the air, end for end: apex up to apex down.
        local f = 1 - math.max(0, self.t) / tp.flip
        self.phi = math.pi * (1 - f) + tp.lean * f
        setAxis(cone, self.phi, self.psi)
        cone.apex[3] = cone.h * (1 - f) + math.sin(math.pi * f) * 14
        if self.t <= 0 then
            cone.apex[3] = 0
            self.sub, self.t = "spin", pick(tp.time, self.phase)
            Camera.knock(2)
            Sfx.play("pin", 0.9)
            game.particles:burst(loose.x, loose.y, 8, Palette.graphite)
        end
    elseif self.sub == "spin" then
        -- On its point, wobbling round, wandering after you.
        self.psi = self.psi + tp.whirl * dt
        self.phi = tp.lean
        setAxis(cone, self.phi, self.psi)
        local p = game.player
        local dx, dy = util.normalize(p.x - loose.x, p.y - loose.y)
        local w = math.sin(self.psi * 0.5) * tp.wobble
        local x = loose.x + (dx - dy * w) * tp.speed * dt
        local y = loose.y + (dy + dx * w) * tp.speed * dt
        if self.box then x, y = self.box:clamp(x, y, cone.r + 2) end
        loose.x, loose.y = x, y
        -- Chips off it in a spiral: one every `every`, a little further round.
        self.chipT = self.chipT - dt
        if self.chipT <= 0 then
            self.chipT = tp.every
            self.spray = self.spray + tp.turn
            local ch = tp.chip
            game.shots[#game.shots + 1] = {
                x = loose.x, y = loose.y - cone.h * 0.6,
                dx = math.cos(self.spray), dy = math.sin(self.spray), speed = ch.speed,
                damage = scaled(e, ch.damage), life = ch.life, sprite = ch.sprite,
                radius = ch.hit * e.reach, grow = e.grow,
            }
            Sfx.play("tick", 1.5)
        end
        bump(game, e, loose.x, loose.y, cone.r + 2, tp.damage)
        if self.t <= 0 then
            self.sub, self.t = "fall", tp.fall
            self.phiFrom = self.phi
        end
    elseif self.sub == "fall" then
        local f = 1 - math.max(0, self.t) / tp.fall
        self.phi = self.phiFrom + (lying - self.phiFrom) * f * f
        setAxis(cone, self.phi, self.psi)
        if self.t <= 0 then
            Camera.knock(1)
            Sfx.play("tick", 0.8)
            game.particles:burst(loose.x, loose.y, 6, Palette.graphite)
            self.from = { x = loose.x, y = loose.y }
            self.sub, self.t = "back", tp.back
        end
    else
        -- Picked up and stood back on its base where it belongs.
        local hx, hy = self:homeSpot(e, CONE)
        local f = 1 - math.max(0, self.t) / tp.back
        loose.x = self.from.x + (hx - self.from.x) * f
        loose.y = self.from.y + (hy - self.from.y) * f
        self.phi = lying + (math.pi - lying) * f
        setAxis(cone, self.phi, self.psi)
        cone.apex[3] = cone.h * f + math.sin(math.pi * f) * 10
        if self.t <= 0 then
            self:home(e, body)
            self.state, self.t = "rest", pick(self.def.cool, self.phase)
            return
        end
    end
    loose.painter:touch()
end

--- drawing --------------------------------------------------------------------

-- The part of the page a shadow may be drawn on: the box, or a screen's worth
-- round the group when there is none.
function StillLife:board()
    local b = self.box
    if b then return b.left, b.top, b:right(), b:bottom() end
    local e = self.e
    return e.x - 240, e.y - 135, e.x + 240, e.y + 135
end

-- A shadow on the floor: every `step`th row of it, clipped to the board. One
-- rectangle a row, so a shadow across the whole box costs a hundred calls.
function StillLife:fillWedge(w, step, shift)
    local x0, y0, x1, y1 = self:board()
    pixelart.fillPolygon(w.poly, y0, y1 - 1, function(x, y, n)
        if (y + shift) % step ~= 0 then return end
        local a, b = math.max(x, x0), math.min(x + n - 1, x1 - 1)
        if b >= a then love.graphics.rectangle("fill", a, y, b - a + 1, 1) end
    end)
end

local function edges(w)
    local p = w.poly
    pixelart.line(floor(p[1]), floor(p[2]), floor(p[3]), floor(p[4]))
    pixelart.line(floor(p[7]), floor(p[8]), floor(p[5]), floor(p[6]))
end

-- Dashes along a line, marching outwards: the bowl's line.
local function dashes(x, y, dx, dy, len, shift)
    for d = 0, len, 1 do
        if floor((d - shift) / 3) % 2 == 0 then
            love.graphics.rectangle("fill", floor(x + dx * d), floor(y + dy * d), 1, 1)
        end
    end
end

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

-- On the floor: the shadows, short or long, the cube's mark and the bowl's line.
function StillLife:drawGround(time)
    local e = self.e
    if not e or not self.lamps then return end
    local sh = self.def.shade

    local shading = self.state == "shade"
    local len = shading and self.len or sh.short
    local ws = self:shadows(e, len or sh.short)
    if shading and self.sub == "hot" then
        for _, w in ipairs(ws) do
            love.graphics.setColor(Palette.slate)
            self:fillWedge(w, 1, 0)
            love.graphics.setColor(Palette.red)
            edges(w)
        end
    elseif shading and self.sub == "tell" then
        local blink = self.t < 0.35 and floor(time * 10) % 2 == 0
        for _, w in ipairs(ws) do
            love.graphics.setColor(Palette.graphite)
            self:fillWedge(w, 3, floor(time * 12))
            love.graphics.setColor(blink and Palette.red or Palette.slate)
            edges(w)
        end
    else
        love.graphics.setColor(Palette.graphite)
        for _, w in ipairs(ws) do self:fillWedge(w, 2, 0) end
    end

    -- What is off the table throws a short shadow of its own while it is on
    -- the floor.
    local loose = self.loose
    if loose and not loose.painter.hidden then
        local lift = loose.piece.lift or (loose.piece.apex and loose.piece.apex[3]) or 0
        if lift < 6 then
            love.graphics.setColor(Palette.graphite)
            for _, l in ipairs(self.lamps) do
                self:fillWedge(wedge(l.x, l.y, loose.x, loose.y, width(loose.piece), sh.short), 2, 0)
            end
        end
    end

    if self.mark then
        local dr = self.def.drop
        love.graphics.setColor(floor(time * 8) % 2 == 0 and Palette.red or Palette.slate)
        dottedRing(self.mark.x, self.mark.y, dr.shock, floor(time * 6))
        love.graphics.setColor(Palette.graphite)
        local f = self.sub == "aim" and 1 - math.max(0, self.t) / dr.aim or 1
        pixelart.circleFill(floor(self.mark.x), floor(self.mark.y), floor(3 + f * 8))
    end
    if self.shockT and self.shockT > 0 and self.shockAt then
        love.graphics.setColor(Palette.red)
        local r = floor(self.def.drop.shock * (1 - self.shockT / 0.3))
        if r > 0 then pixelart.circleOutline(floor(self.shockAt.x), floor(self.shockAt.y), r) end
    end

    if self.state == "roll" and self.sub == "wind" and self.aim then
        local a = self.aim
        love.graphics.setColor(floor(time * 10) % 2 == 0 and Palette.red or Palette.slate)
        dashes(a.x, a.y, a.dx, a.dy, a.len, time * 30)
    end
end

-- A lamp: a bulb in a ring of rays, blinking red while it is swinging round
-- for a shade -- the lamp going where it is going is the tell.
local function drawLamp(l, warn)
    local x, y = floor(l.x), floor(l.y)
    love.graphics.setColor(Palette.ink)
    pixelart.circleFill(x, y, 4)
    love.graphics.setColor(warn and Palette.red or Palette.paper)
    pixelart.circleFill(x, y, 3)
    love.graphics.setColor(warn and Palette.red or Palette.slate)
    for k = 0, 7 do
        local a = k * TAU / 8
        love.graphics.rectangle("fill", floor(x + math.cos(a) * 6.5), floor(y + math.sin(a) * 6.5), 1, 1)
    end
end

-- Over the crowd: the lamps, and whatever is off the table.
function StillLife:drawAir(time, e)
    if not self.lamps then return end
    local warn = self.state == "shade" and self.sub == "tell" and floor(time * 10) % 2 == 0
    for _, l in ipairs(self.lamps) do drawLamp(l, warn) end
    local loose = self.loose
    if loose then loose.painter:draw(loose.x, loose.y) end
end

return StillLife
