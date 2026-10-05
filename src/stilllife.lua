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
-- faces it is the paper, the side that turns away is slate. Every solid throws
-- its shadow across the floor directly away from it -- on the table or off it,
-- wherever it has got to. Most of the time those are short smudges, and what
-- they are for is teaching you to read the light.
--
-- **The shade** is the move that cashes that in. The lamp swings round to the
-- far side of the group from you and every shadow grows out across the box,
-- hatched while it is counted in, then filled -- and a filled shadow hurts.
-- Each solid throws its own, fanned out from the lamp, so there are gaps of
-- light between them as well as round them; a cube sitting out on the page or a
-- sphere half way down its line throws one from where it is, so a shade with
-- the pieces spread is a different shape from one with them together. From the
-- middle third the lamp keeps moving while they are filled, so the shadows
-- sweep and you walk with them; in the last third there are two lamps, and
-- two fans.
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
-- **The lower it gets, the more of it moves at once.** One move at a time in
-- the first third; from the middle third two -- the cube coming down while the
-- sphere is rolling, or either under a shade -- and three in the last. Each
-- piece can only be doing one thing, and there is only one shade at a time.
--
-- **A piece off the table can be hit.** It is the boss as much as the group
-- is, so while it is out it is stood for by a body of its own on the page
-- (`stillpiece` in src/enemy.lua) that everything in the game can find, aim at
-- and hurt, and whatever it takes comes off the boss (Enemy:hurt). It never
-- dies of it: it is only ever taken off the page again, when the piece goes
-- home. Off the page in the air, it is not there to be hit.
--
-- **Glue holds the table.** A glued still life cannot move its lamp, so a
-- shade it was counting in is dropped, nothing new is started, and it cannot be
-- lifted to somewhere nearer you. What is already off the table goes on doing
-- what it was doing: glue holds the group, not a cube in the air.
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

-- Which piece each move takes off the table; the shade takes none.
local PIECE = { drop = CUBE, roll = SPHERE, top = CONE }

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
        coolT = 1.6,
        acts = {},        -- the moves going on now, each its own clock
        out = {},         -- the pieces off the table, by index
        hopping = nil,    -- the table being lifted somewhere nearer
        last = nil,
        lamps = nil,
        e = nil,
    }, StillLife)
end

function StillLife:busy()
    return #self.acts > 0 or self.hopping ~= nil
end

-- The move of this kind going on now, if one is.
function StillLife:act(kind)
    for _, a in ipairs(self.acts) do
        if a.kind == kind then return a end
    end
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

    -- Killed through a piece. Enemy:hurt on a piece never answers that it
    -- died -- the piece is not what dies -- so the group notices for itself, on
    -- its own turn, which is a place in the frame a kill is safe to make.
    if e.hp <= 0 then
        e.hitCooldown = 1
        game:killEnemyAt(e)
        return
    end
    if self.shockT then self.shockT = math.max(0, self.shockT - dt) end

    -- The phase, at the eye's thirds: another piece joins in, and the lamp
    -- learns something. Whatever it was in the middle of is put back.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        self:clear(game, e)
        self.coolT = 0.9
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
    -- in is dropped, a lift to somewhere else is put down where it is, and
    -- nothing new is started; what is off the table already carries on.
    local stuck = e.frozen > 0
    if stuck then
        for i = #self.acts, 1, -1 do
            local a = self.acts[i]
            if a.kind == "shade" and a.sub == "tell" then table.remove(self.acts, i) end
        end
        if self.hopping then
            e.hop, self.hopping = 0, nil
        end
        e.blowT = 0
    end

    if not self:act("shade") then self:drift(dt) end
    if self.hopping then
        self:stepHop(dt, game, e)
    elseif not stuck then
        self.coolT = self.coolT - dt
        if self.coolT <= 0 then self:choose(game, e, body) end
    end

    for i = #self.acts, 1, -1 do
        local a = self.acts[i]
        a.t = a.t - dt
        if self["step_" .. a.kind](self, a, dt, game, e, body) then
            table.remove(self.acts, i)
        end
    end

    self:placeLamps(e)
    self:light(e, body)
    self:syncParts()
end

-- Every piece back on the table and every move dropped: the change of phase.
function StillLife:clear(game, e)
    local body = e.plaster
    for k, loose in pairs(self.out) do
        game.particles:burst(loose.x, loose.y, 8, Palette.graphite)
        self:home(e, body, k)
    end
    self.acts, self.mark, self.hopping = {}, nil, nil
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
    for _, loose in pairs(self.out) do
        loose.painter.lamp[1] = l.x - loose.x
        loose.painter.lamp[2] = l.y - loose.y
        loose.painter.lamp[3] = high
    end
end

-- Whether a move can start: the shade if no shade is going, a piece's move if
-- that piece is on the table.
function StillLife:free(kind)
    if self:act(kind) then return false end
    local k = PIECE[kind]
    return not (k and self.out[k])
end

-- The next move, once the last one started has had its `cool`: anything free
-- that is not the move it started last, up to `together` going at once. Or,
-- when you are far off and nothing is going on, the table lifted nearer.
function StillLife:choose(game, e, body)
    if #self.acts >= pick(self.def.together, self.phase) then return end
    local p = game.player
    local dist = util.len(p.x - e.x, p.y - e.y)
    local mv = self.def.move
    if #self.acts == 0 and next(self.out) == nil and dist > mv.far and self.last ~= "move" then
        local dx, dy = (p.x - e.x) / dist, (p.y - e.y) / dist
        local go = math.min(mv.reach, dist - mv.near)
        local tx, ty = e.x + dx * go, e.y + dy * go
        if self.box then tx, ty = self.box:clamp(tx, ty, e.radius + 8) end
        self.hopping = { fx = e.x, fy = e.y, tx = tx, ty = ty, t = mv.time }
        self.last = "move"
        return
    end
    local options = {}
    for _, kind in ipairs(self.def.moves[self.phase]) do
        if self:free(kind) and kind ~= self.last then options[#options + 1] = kind end
    end
    if #options == 0 then
        for _, kind in ipairs(self.def.moves[self.phase]) do
            if self:free(kind) then options[#options + 1] = kind end
        end
    end
    if #options == 0 then
        self.coolT = 0.3
        return
    end
    local kind = options[love.math.random(#options)]
    self.last = kind
    local a = self["start_" .. kind](self, game, e, body)
    a.kind = kind
    self.acts[#self.acts + 1] = a
    self.coolT = pick(self.def.cool, self.phase)
end

-- The whole group lifted and set down nearer you: how a thing that never walks
-- keeps up. A hop rather than a slide, so it is the table being rearranged and
-- not the table creeping.
function StillLife:stepHop(dt, game, e)
    local h, mv = self.hopping, self.def.move
    h.t = h.t - dt
    local f = 1 - math.max(0, h.t) / mv.time
    e.x = h.fx + (h.tx - h.fx) * f
    e.y = h.fy + (h.ty - h.fy) * f
    e.hop = floor(math.sin(math.pi * f) * mv.high + 0.5)
    if h.t <= 0 then
        e.hop, self.hopping = 0, nil
        Sfx.play("tick", 0.8)
        Camera.knock(1)
        game.particles:burst(e.x, e.y + FOOT, 6, Palette.graphite)
        self.coolT = math.max(self.coolT, 0.5)
    end
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

-- How high a loose piece is off the floor: a piece in the air throws no
-- shadow on the floor you could stand in, and is not there to be hit.
local function lift(p)
    if p.kind == "cone" then return p.apex[3] end
    return p.lift or 0
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

-- Every shadow on the page this frame, at `len`: one per lamp per piece, on
-- the table or out on the floor wherever it has got to. A piece in the air or
-- out of sight throws none.
function StillLife:shadows(e, len)
    local out = {}
    for _, l in ipairs(self.lamps) do
        for k, p in ipairs(e.plaster.pieces) do
            local loose = self.out[k]
            if loose then
                if not loose.painter.hidden and lift(loose.piece) < 6 then
                    out[#out + 1] = wedge(l.x, l.y, loose.x, loose.y, width(loose.piece), len)
                end
            elseif not p.hidden then
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
    Sfx.play("tick", 0.7)
    return {
        sub = "tell", t = pick(sh.tell, self.phase), len = sh.short,
        swing = pick(sh.swing, self.phase) * (love.math.random() < 0.5 and -1 or 1),
    }
end

function StillLife:step_shade(a, dt, game, e)
    local sh = self.def.shade
    if a.sub == "tell" then
        local total = pick(sh.tell, self.phase)
        local f = math.min(1, (1 - math.max(0, a.t) / total) / 0.6)
        local ease = f * f * (3 - 2 * f)
        for _, l in ipairs(self.lamps) do l.a = l.from + (l.to - l.from) * ease end
        a.len = sh.short + (sh.length - sh.short) * ease
        if a.t <= 0 then
            a.sub, a.t, a.len = "hot", pick(sh.hot, self.phase), sh.length
            Camera.knock(2)
            Sfx.play("pin", 0.8)
        end
    elseif a.sub == "hot" then
        local hot = pick(sh.hot, self.phase)
        for _, l in ipairs(self.lamps) do l.a = l.a + a.swing / hot * dt end
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
        if a.t <= 0 then a.sub, a.t = "fade", sh.fade end
    else
        a.len = sh.short + (sh.length - sh.short) * math.max(0, a.t) / sh.fade
        if a.t <= 0 then return true end
    end
end

--- off the table --------------------------------------------------------------

-- The body that stands for a piece while it is off the table: on the page in
-- the horde, so every weapon finds it the way it finds anything else, and
-- appended *after* the boss. That is what makes it safe to take back off from
-- inside the boss's own turn: the horde is walked backwards (Game:updateEnemies,
-- and every weapon's pass), so everything after the boss has already been
-- walked when the boss is.
local function standIn(game, e, damage)
    local Enemy = require("src.enemy")
    local part = Enemy.new("stillpiece", e.x, e.y)
    part.stand = e
    part.damage = damage
    part.ghost = true
    game.enemies[#game.enemies + 1] = part
    return part
end

local function dropStandIn(game, part)
    part.gone = true
    for i = #game.enemies, 1, -1 do
        if game.enemies[i] == part then
            table.remove(game.enemies, i)
            return
        end
    end
end

-- A piece taken off the table into a painter of its own, drawn where it is on
-- the page rather than where it stood in the group.
function StillLife:lift(game, e, body, k, piece, damage)
    local x, y = spot(e, body.pieces[k])
    body.pieces[k].hidden = true
    body:touch()
    local loose = { k = k, x = x, y = y, piece = piece, painter = Plaster.new({ piece }, 0),
                    part = standIn(game, e, scaled(e, damage)) }
    self.out[k] = loose
    self.game = game
    return loose
end

-- And put back: the piece is shown in the group again, turned the way it came
-- back (a cube) or stood up again (the cone and sphere have no way round).
function StillLife:home(e, body, k)
    local loose = self.out[k]
    if not loose then return end
    local p = body.pieces[k]
    if p.kind == "cube" then
        -- Put down flat: whichever way it is turned, set square on the floor
        -- about the upright, so a cube is never left balanced on an edge.
        local q = loose.piece
        local yaw = math.atan2(q.ax[2], q.ax[1])
        p.ax[1], p.ax[2], p.ax[3] = math.cos(yaw), math.sin(yaw), 0
        p.ay[1], p.ay[2], p.ay[3] = -math.sin(yaw), math.cos(yaw), 0
        p.az[1], p.az[2], p.az[3] = 0, 0, 1
    end
    p.hidden = false
    body:touch()
    if self.game then dropStandIn(self.game, loose.part) end
    self.out[k] = nil
end

-- Every stand-in off the page: the boss has gone (Game:killEnemy asks), and
-- what was standing for its pieces goes with it.
function StillLife:dropParts(game)
    for k, loose in pairs(self.out) do
        dropStandIn(game, loose.part)
        self.out[k] = nil
    end
end

-- The stand-ins follow their pieces: at the middle of what you see, as wide as
-- it is, and not there at all while the piece is in the air or out of sight.
function StillLife:syncParts()
    for _, loose in pairs(self.out) do
        local part, piece = loose.part, loose.piece
        local up = lift(piece)
        local away = loose.painter.hidden or up > 10
        local tall = piece.kind == "cube" and piece.half or piece.kind == "sphere" and piece.r
            or piece.h * 0.4
        part.x, part.y = loose.x, loose.y - tall
        part.radius = width(piece) + 1
        part.ghost = away
        if away then part.hitCooldown = math.max(part.hitCooldown, 0.1) end
    end
end

-- Where a piece's home spot in the group is on the page.
function StillLife:homeSpot(e, k)
    return spot(e, e.plaster.pieces[k])
end

--- the cube -------------------------------------------------------------------

function StillLife:start_drop(game, e, body)
    local dr = self.def.drop
    local cube = Plaster.cube(0, 0, body.pieces[CUBE].half)
    local src = body.pieces[CUBE]
    for i = 1, 3 do cube.ax[i], cube.ay[i], cube.az[i] = src.ax[i], src.ay[i], src.az[i] end
    self:lift(game, e, body, CUBE, cube, dr.damage)
    Sfx.play("tick", 0.6)
    return { sub = "up", t = dr.up }
end

function StillLife:step_drop(a, dt, game, e, body)
    local dr = self.def.drop
    local loose = self.out[CUBE]
    local cube = loose.piece
    if a.sub == "up" then
        local f = 1 - math.max(0, a.t) / dr.up
        cube.lift = dr.high * f * f
        Plaster.turn(cube, 1, 0.4, 0, dt * 12)
        loose.painter:touch()
        if a.t <= 0 then
            local p = game.player
            local x, y = p.x, p.y
            if self.box then x, y = self.box:clamp(x, y, cube.half + 4) end
            self.mark = { x = x, y = y, t = dr.aim }
            loose.painter.hidden = true
            a.sub, a.t = "aim", dr.aim
        end
    elseif a.sub == "aim" then
        self.mark.t = a.t
        if a.t <= 0 then
            loose.x, loose.y = self.mark.x, self.mark.y
            loose.painter.hidden = false
            a.sub, a.t = "down", dr.down
        end
    elseif a.sub == "down" then
        local f = math.max(0, a.t) / dr.down
        cube.lift = dr.high * f * f
        Plaster.turn(cube, 0.3, 1, 0, dt * 12)
        loose.painter:touch()
        if a.t <= 0 then
            cube.lift = 0
            -- Square on the floor, as it would land: anything else balances a
            -- cube on an edge for as long as it sits there.
            local yaw = math.atan2(cube.ax[2], cube.ax[1])
            cube.ax[1], cube.ax[2], cube.ax[3] = math.cos(yaw), math.sin(yaw), 0
            cube.ay[1], cube.ay[2], cube.ay[3] = -math.sin(yaw), math.cos(yaw), 0
            cube.az[1], cube.az[2], cube.az[3] = 0, 0, 1
            loose.painter:touch()
            self.mark = nil
            local p = game.player
            if util.len(p.x - loose.x, p.y - loose.y) < dr.shock + p.radius
                and p:hurt(scaled(e, dr.damage)) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
            self.shockAt, self.shockT = { x = loose.x, y = loose.y }, 0.3
            Camera.knock(4)
            Sfx.play("pin", 0.5)
            game.particles:burst(loose.x, loose.y, 18, Palette.red)
            for _ = 1, 8 do
                game.particles:crumb(loose.x, loose.y, nil, nil, cube.half, Palette.graphite)
            end
            a.sub, a.t = "sit", dr.sit
        end
    elseif a.sub == "sit" then
        if a.t <= 0 then
            a.fx, a.fy = loose.x, loose.y
            a.sub, a.t = "back", dr.back
        end
    else
        local hx, hy = self:homeSpot(e, CUBE)
        local f = 1 - math.max(0, a.t) / dr.back
        loose.x = a.fx + (hx - a.fx) * f
        loose.y = a.fy + (hy - a.fy) * f
        cube.lift = math.sin(math.pi * f) * dr.hop
        Plaster.turn(cube, hy - a.fy, a.fx - hx, 0, dt * 6)
        loose.painter:touch()
        if a.t <= 0 then
            self:home(e, body, CUBE)
            Sfx.play("tick", 0.9)
            return true
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
    return {
        sub = "wind", t = rl.wind,
        aim = { x = x, y = y, dx = dx, dy = dy,
                len = reach(self.box, x, y, dx, dy, rl.length, body.pieces[SPHERE].r + 2) },
    }
end

function StillLife:step_roll(a, dt, game, e, body)
    local rl = self.def.roll
    if a.sub == "wind" then
        e.blowT = math.max(0, a.t)
        if a.t <= 0 then
            e.blowT = 0
            local ball = Plaster.sphere(0, 0, body.pieces[SPHERE].r)
            self:lift(game, e, body, SPHERE, ball, rl.damage)
            a.gone = 0
            a.sub = "out"
            Sfx.play("tick", 0.8)
        end
        return
    end
    local loose = self.out[SPHERE]
    local aim = a.aim
    local r = loose.piece.r
    if a.sub == "out" then
        a.gone = math.min(aim.len, a.gone + rl.speed * dt)
        loose.x, loose.y = aim.x + aim.dx * a.gone, aim.y + aim.dy * a.gone
        if a.gone >= aim.len then
            a.sub = "back"
            Camera.knock(2)
            Sfx.play("tick", 1.0)
            game.particles:burst(loose.x, loose.y, 6, Palette.graphite)
        end
    else
        local hx, hy = self:homeSpot(e, SPHERE)
        local dx, dy, d = util.normalize(hx - loose.x, hy - loose.y)
        local step = rl.speed * rl.back * dt
        if d <= step then
            self:home(e, body, SPHERE)
            Sfx.play("tick", 0.9)
            return true
        end
        loose.x, loose.y = loose.x + dx * step, loose.y + dy * step
    end
    if love.math.random() < dt * 20 then
        game.particles:crumb(loose.x, loose.y + r, nil, nil, 2, Palette.graphite)
    end
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
    self:lift(game, e, body, CONE, cone, self.def.top.damage)
    Sfx.play("tick", 0.7)
    return { sub = "flip", t = self.def.top.flip, phi = math.pi, psi = 0,
             spray = love.math.random() * TAU, chipT = 0 }
end

function StillLife:step_top(a, dt, game, e, body)
    local tp = self.def.top
    local loose = self.out[CONE]
    local cone = loose.piece
    local lying = math.pi / 2 - math.atan(cone.r / cone.h)
    if a.sub == "flip" then
        -- Over in the air, end for end: apex up to apex down.
        local f = 1 - math.max(0, a.t) / tp.flip
        a.phi = math.pi * (1 - f) + tp.lean * f
        setAxis(cone, a.phi, a.psi)
        cone.apex[3] = cone.h * (1 - f) + math.sin(math.pi * f) * 14
        if a.t <= 0 then
            cone.apex[3] = 0
            a.sub, a.t = "spin", pick(tp.time, self.phase)
            Camera.knock(2)
            Sfx.play("pin", 0.9)
            game.particles:burst(loose.x, loose.y, 8, Palette.graphite)
        end
    elseif a.sub == "spin" then
        -- On its point, wobbling round, wandering after you.
        a.psi = a.psi + tp.whirl * dt
        a.phi = tp.lean
        setAxis(cone, a.phi, a.psi)
        local p = game.player
        local dx, dy = util.normalize(p.x - loose.x, p.y - loose.y)
        local w = math.sin(a.psi * 0.5) * tp.wobble
        local x = loose.x + (dx - dy * w) * tp.speed * dt
        local y = loose.y + (dy + dx * w) * tp.speed * dt
        if self.box then x, y = self.box:clamp(x, y, cone.r + 2) end
        loose.x, loose.y = x, y
        -- Chips off it in a spiral: one every `every`, a little further round.
        a.chipT = a.chipT - dt
        if a.chipT <= 0 then
            a.chipT = tp.every
            a.spray = a.spray + tp.turn
            local ch = tp.chip
            game.shots[#game.shots + 1] = {
                x = loose.x, y = loose.y - cone.h * 0.6,
                dx = math.cos(a.spray), dy = math.sin(a.spray), speed = ch.speed,
                damage = scaled(e, ch.damage), life = ch.life, sprite = ch.sprite,
                radius = ch.hit * e.reach, grow = e.grow,
            }
            Sfx.play("tick", 1.5)
        end
        if a.t <= 0 then
            a.sub, a.t, a.from = "fall", tp.fall, a.phi
        end
    elseif a.sub == "fall" then
        local f = 1 - math.max(0, a.t) / tp.fall
        a.phi = a.from + (lying - a.from) * f * f
        setAxis(cone, a.phi, a.psi)
        if a.t <= 0 then
            Camera.knock(1)
            Sfx.play("tick", 0.8)
            game.particles:burst(loose.x, loose.y, 6, Palette.graphite)
            a.fx, a.fy = loose.x, loose.y
            a.sub, a.t = "back", tp.back
        end
    else
        -- Picked up and stood back on its base where it belongs.
        local hx, hy = self:homeSpot(e, CONE)
        local f = 1 - math.max(0, a.t) / tp.back
        loose.x = a.fx + (hx - a.fx) * f
        loose.y = a.fy + (hy - a.fy) * f
        a.phi = lying + (math.pi - lying) * f
        setAxis(cone, a.phi, a.psi)
        cone.apex[3] = cone.h * f + math.sin(math.pi * f) * 10
        if a.t <= 0 then
            self:home(e, body, CONE)
            return true
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

-- A shadow's two long sides, a pixel at a time and only inside the board, the
-- way its fill is: a side running on past the edge of the box would be a
-- shadow the page says is there and the hit test says is not.
function StillLife:edges(w)
    local x0, y0, x1, y1 = self:board()
    local p = w.poly
    for _, side in ipairs({ { p[1], p[2], p[3], p[4] }, { p[7], p[8], p[5], p[6] } }) do
        local ax, ay, bx, by = side[1], side[2], side[3], side[4]
        local n = math.max(1, floor(math.max(math.abs(bx - ax), math.abs(by - ay))))
        for i = 0, n do
            local x, y = floor(ax + (bx - ax) * i / n), floor(ay + (by - ay) * i / n)
            if x >= x0 and x < x1 and y >= y0 and y < y1 then
                love.graphics.rectangle("fill", x, y, 1, 1)
            end
        end
    end
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

    local shade = self:act("shade")
    local ws = self:shadows(e, shade and shade.len or sh.short)
    if shade and shade.sub == "hot" then
        for _, w in ipairs(ws) do
            love.graphics.setColor(Palette.slate)
            self:fillWedge(w, 1, 0)
            love.graphics.setColor(Palette.red)
            self:edges(w)
        end
    elseif shade and shade.sub == "tell" then
        local blink = shade.t < 0.35 and floor(time * 10) % 2 == 0
        for _, w in ipairs(ws) do
            love.graphics.setColor(Palette.graphite)
            self:fillWedge(w, 3, floor(time * 12))
            love.graphics.setColor(blink and Palette.red or Palette.slate)
            self:edges(w)
        end
    else
        love.graphics.setColor(Palette.graphite)
        for _, w in ipairs(ws) do self:fillWedge(w, 2, 0) end
    end

    if self.mark then
        local dr = self.def.drop
        love.graphics.setColor(floor(time * 8) % 2 == 0 and Palette.red or Palette.slate)
        dottedRing(self.mark.x, self.mark.y, dr.shock, floor(time * 6))
        love.graphics.setColor(Palette.graphite)
        local f = 1 - math.max(0, self.mark.t) / dr.aim
        pixelart.circleFill(floor(self.mark.x), floor(self.mark.y), floor(3 + f * 8))
    end
    if self.shockT and self.shockT > 0 and self.shockAt then
        love.graphics.setColor(Palette.red)
        local r = floor(self.def.drop.shock * (1 - self.shockT / 0.3))
        if r > 0 then pixelart.circleOutline(floor(self.shockAt.x), floor(self.shockAt.y), r) end
    end

    local roll = self:act("roll")
    if roll and roll.sub == "wind" then
        local aim = roll.aim
        love.graphics.setColor(floor(time * 10) % 2 == 0 and Palette.red or Palette.slate)
        dashes(aim.x, aim.y, aim.dx, aim.dy, aim.len, time * 30)
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

-- How long a hit lights a loose piece, and the paper stage of it: the body's
-- own numbers (Enemy:draw), so a piece taking a hit flashes like the group does.
local HIT_FLASH, HIT_WHITE = 0.14, 0.06

-- Over the crowd: the lamps, and whatever is off the table -- lit, rimmed and
-- blown out by a hit the way the group is, off its stand-in's flash.
function StillLife:drawAir(time, e)
    if not self.lamps then return end
    local shade = self:act("shade")
    local warn = shade and shade.sub == "tell" and floor(time * 10) % 2 == 0
    for _, l in ipairs(self.lamps) do drawLamp(l, warn) end
    for _, loose in pairs(self.out) do
        local flash = loose.part.flash
        if flash > 0 then
            love.graphics.setColor(Palette.red)
            loose.painter:drawMask(loose.x, loose.y, 1)
            love.graphics.setColor(flash > HIT_FLASH - HIT_WHITE and Palette.paper or Palette.blush)
            loose.painter:drawMask(loose.x, loose.y, 0)
        else
            loose.painter:draw(loose.x, loose.y)
        end
    end
end

return StillLife
