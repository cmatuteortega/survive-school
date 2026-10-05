-- The tesseract's mind: MATHS's encore, and the fight in the book about
-- *dimension*.
--
-- The die is a fight about reading a number. The tesseract is what the squared
-- page was always a slice of: a cube of cubes, turning through a direction the
-- page does not have, and its fight is about which side of a shape you are on
-- -- inside or outside, on a square or off it -- when the shape turns into
-- something else. Every move is drawn first on the page's own squares, in the
-- shape it is going to be, and then it is.
--
-- **Inside-out.** It stops, and two squares are drawn round it on the floor,
-- turned the way the cube is turned: the inner cube's and the outer cube's, the
-- band between them dotted red. Then it turns half over through the fourth
-- dimension -- the inner cube flows out through the outer and becomes it -- and
-- the band between the two is where that happened: anything in it is crushed,
-- and the crowd caught there is flung out of it. The way out is either side: out
-- past the outer square, or *in*, right up against it, inside the inner one,
-- which is the one move in the book whose safe place is next to the boss. From
-- the second phase it turns back again straight after -- **inside out**, the
-- other way: the middle and a rim round the outside go off, and the band you
-- stood in to dodge the first is the only floor that is not. At the last third
-- the squares turn as well while they go.
--
-- **The corners.** It holds still, and its corners blink red: the outer eight,
-- then all sixteen. Then they fly off it, each straight out the way it sticks
-- out on the page -- the far corners fast and the near ones slow -- so the volley
-- is the shape of the thing you were just looking at, thrown. At the last third
-- it throws twice, turned between.
--
-- **The net.** It unfolds onto the page as a net of eight cubes, the cross
-- Dali painted, laid out from the square it hovers over towards you and
-- numbered one to eight. The cubes go off in the order of their numbers, one
-- after the other, so the net is a sequence you read and stay ahead of: first in
-- order from the root out to the tip, then from the tip back, then -- at the last
-- third -- in an order you can only know by reading the numbers.
--
-- **Through the fourth dimension**, from the second phase, when you have got
-- away from it: it turns out of the page and is not there, a dashed square comes
-- down on where you are standing, and it turns back into the page there with a
-- square shock round it. The die's recast without the leap: it did not go up,
-- it went *elsewhere*.
--
-- **Glue holds a tell.** An inside-out or a volley still being counted in, or a
-- net none of whose cubes has gone off, is dropped and it rests -- the
-- tool-shaped counterplay every boss in the book has.
--
-- The body is src/tesseract.lua, projected every frame; this file turns it,
-- lays its shapes on the floor and reads whether you are in them.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local Font = require("src.font")
local Tesseract = require("src.tesseract")
local pixelart = require("src.pixelart")
local util = require("src.util")

local TesseractBoss = {}
TesseractBoss.__index = TesseractBoss

local TAU = math.pi * 2
local floor, abs, max, min, cos, sin = math.floor, math.abs, math.max, math.min, math.cos, math.sin

-- The entrance: it turns into the page out of nothing, spinning down to its
-- walking pace -- the reverse of the move it gets about by later.
local ENTER_TIME = 1.3
-- How long the square shock of its coming back into the page is drawn going out.
local SHOCK_TIME = 0.3

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

-- Cells of the page snapped to its own squares, the die's way.
local function snap(v, size) return floor(v / size) * size end

function TesseractBoss.new(def)
    return setmetatable({
        def = def.tesseract,
        state = "enter", t = ENTER_TIME,
        phase = 1,
        last = nil,
        flip = nil,   -- an inside-out: its squares and which passes are left
        net = nil,    -- the net of cubes on the floor
        mark = nil,   -- where it will come back into the page
        shockT = 0,
        e = nil,
    }, TesseractBoss)
end

function TesseractBoss:busy()
    return self.state ~= "idle"
end

--- the loop -------------------------------------------------------------------

function TesseractBoss:update(dt, game, e)
    self.e = e
    local body = e.tesseract
    if dt <= 0 then return end
    self.shockT = max(0, self.shockT - dt)

    -- The phase, at the eye's thirds. The last is announced: it spins up hard
    -- for a moment, which is the body saying it is about to mean it.
    local share = e.hp / e.maxHp
    body.hurt = 1 - share
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        game.particles:burst(e.x, e.y - 6, phase >= 3 and 28 or 14, Palette.red)
        Camera.knock(phase >= 3 and 3 or 1)
        if phase >= 3 then
            game:say("HYPERSPACE!")
            self.surge = 1.2
        end
    end
    if self.surge then
        self.surge = self.surge - dt
        if self.surge <= 0 then self.surge = nil end
    end

    -- Glue answers a tell: what is still being counted in is dropped, and it
    -- rests. A net is only dropped before any of it has gone off -- once the
    -- sequence has started it is on the floor, not in the boss.
    if e.frozen > 0 then
        local net = self.net
        if self.state == "flipTell" or self.state == "cornersTell"
            or (self.state == "unfold" and net and net.gone == 0) then
            self:calm(e)
            self:rest(e, 0.4)
        end
    end

    self.t = self.t - dt
    self[self.state](self, dt, game, e, body)

    -- How fast it turns: what the move wants, and a burst on top of that when
    -- the last third arrives.
    body.spin = (self.spinWant or 1) * (self.surge and 3 or 1)
    body:update(dt)
end

-- Everything a tell had going put back.
function TesseractBoss:calm(e)
    local body = e.tesseract
    self.flip, self.net, self.volleys = nil, nil, nil
    body.flip, body.shake, body.hot = 0, 0, nil
    self.spinWant = 1
end

function TesseractBoss:rest(e, t)
    self.state, self.t = "resting", t
    e.drive = { hold = true }
end

function TesseractBoss:resting(dt, game, e, body)
    e.drive = { hold = true }
    body.shake = 0
    if self.t <= 0 then
        self.state = "idle"
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.6
    end
end

--- the entrance ---------------------------------------------------------------

function TesseractBoss:enter(dt, game, e, body)
    e.drive = { hold = true }
    local f = 1 - max(0, self.t) / ENTER_TIME
    body.fold = f * f
    self.spinWant = 1 + (1 - f) * 5
    if self.t <= 0 then
        body.fold, self.spinWant = 1, 1
        game.particles:burst(e.x, e.y - 6, 16, Palette.red)
        Camera.knock(2)
        self.state, self.t = "idle", 0.8
    end
end

--- walking about --------------------------------------------------------------

function TesseractBoss:idle(dt, game, e)
    e.drive = nil
    if self.t <= 0 and e.frozen <= 0 then self:choose(game, e) end
end

-- An inside-out for whoever is near enough to be in the band; the corners for
-- whoever is further off; the net either way; and from the second phase, when
-- you have got well away, through the fourth dimension to you. The last move
-- is marked down so it is never the same thing three times.
function TesseractBoss:choose(game, e)
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local outer = pick(self.def.flip.outer, self.phase)
    local w = {
        flip = d < outer * 1.1 and 1.4 or 0.4,
        corners = d > 50 and 1.1 or 0.6,
        unfold = 0.9,
        fold = self.phase >= 2 and (d > self.def.fold.far and 2.0 or 0.2) or 0,
    }
    if self.last then w[self.last] = w[self.last] * 0.3 end
    local sum = 0
    for _, v in pairs(w) do sum = sum + v end
    local r = love.math.random() * sum
    local move = "unfold"
    for _, k in ipairs({ "flip", "corners", "unfold", "fold" }) do
        r = r - w[k]
        if r <= 0 then move = k break end
    end
    self.last = move
    self[move .. "Start"](self, game, e, e.tesseract)
end

--- inside-out -----------------------------------------------------------------

-- Two squares round it, turned the way the cube is: the passes it will make,
-- the band first and, from the second phase, the inside-out straight after.
function TesseractBoss:flipStart(game, e, body)
    local f = self.def.flip
    local turn = pick(f.turn, self.phase)
    self.flip = {
        x = e.x, y = e.y,
        a = body.yaw,
        inner = f.inner, outer = pick(f.outer, self.phase), rim = f.rim,
        turn = turn * (love.math.random() < 0.5 and -1 or 1),
        passes = self.phase >= 2 and { "band", "inverse" } or { "band" },
        pass = 1, f = 0,
    }
    self.state, self.t = "flipTell", pick(f.tell, self.phase)
    e.drive = { hold = true }
    Sfx.play("ruler", 0.7)
end

function TesseractBoss:flipTell(dt, game, e, body)
    e.drive = { hold = true }
    body.shake = 0.4
    self.spinWant = 0.4
    if self.t <= 0 then
        body.shake = 0
        self.state, self.t = "flipHot", self.def.flip.hot
        self.flip.f, self.flip.flung = 0, false
        Camera.knock(2)
        Sfx.play("transition2", 1.3)
    end
end

-- Where (x, y) is against the squares, in the squares' own frame: how far out
-- it is, as the half-width of the square it is on the edge of.
local function squareReach(s, x, y, a)
    local dx, dy = x - s.x, y - s.y
    local c, sn = cos(a), sin(a)
    return max(abs(dx * c + dy * sn), abs(-dx * sn + dy * c))
end

-- Whether a reach is in what a pass sets off: the band between the squares, or
-- -- inside out -- the middle and a rim round the outer one.
local function inPass(s, kind, m)
    if kind == "band" then return m > s.inner and m < s.outer end
    return m < s.inner or (m > s.outer and m < s.outer + s.rim)
end

function TesseractBoss:flipHot(dt, game, e, body)
    e.drive = { hold = true }
    local s = self.flip
    local hot = self.def.flip.hot
    local f = 1 - max(0, self.t) / hot
    s.f = f
    -- Half a turn through w, eased, which is the inner cube becoming the outer.
    body.flip = math.pi * (f * f * (3 - 2 * f))
    self.spinWant = 0.4
    local kind = s.passes[s.pass]
    local a = s.a + s.turn * f

    local p = game.player
    if inPass(s, kind, squareReach(s, p.x, p.y, a)) then
        if p:hurt(scaled(e, self.def.flip.damage)) then
            game.particles:burst(p.x, p.y, 6, Palette.red)
        end
    end
    -- And the crowd caught in it, flung out of it once as it goes off: crushed
    -- between the cubes is somewhere nothing gets to stay.
    if not s.flung then
        s.flung = true
        for _, o in ipairs(game.enemies) do
            if o ~= e and not o.def.boss and inPass(s, kind, squareReach(s, o.x, o.y, a)) then
                local nx, ny = util.normalize(o.x - s.x, o.y - s.y)
                if nx == 0 and ny == 0 then nx = 1 end
                o:knockback(nx, ny, self.def.flip.fling)
            end
        end
    end

    if self.t <= 0 then
        -- Half a turn of a tesseract is the same tesseract, so it is put back
        -- to nothing without a jump.
        body.flip = 0
        s.a = s.a + s.turn
        game.particles:burst(e.x, e.y - 6, 10, Palette.red)
        if s.pass < #s.passes then
            s.pass = s.pass + 1
            self.state, self.t = "flipTell", self.def.flip.again
            Sfx.play("ruler", 0.9)
        else
            self.flip = nil
            self.spinWant = 1
            self:rest(e, pick(self.def.flip.rest, self.phase))
        end
    end
end

--- the corners ----------------------------------------------------------------

-- Which corners: the outer eight, or all sixteen. Picked off how far out they
-- stick on the page now, which is what you are looking at when they blink.
function TesseractBoss:pickCorners(body)
    local all = pick(self.def.corners.count, self.phase) >= 16
    local list = {}
    for i = 1, #Tesseract.CORNERS do list[i] = i end
    table.sort(list, function(a, b) return body:reachOf(a) > body:reachOf(b) end)
    local hot = {}
    for k = 1, all and 16 or 8 do hot[list[k]] = true end
    return hot
end

function TesseractBoss:cornersStart(game, e, body)
    self.volleys = pick(self.def.corners.volleys, self.phase)
    body.hot = self:pickCorners(body)
    self.state, self.t = "cornersTell", pick(self.def.corners.tell, self.phase)
    e.drive = { hold = true }
end

-- Held nearly still while it aims, so the shape it is about to throw is a shape
-- you can read.
function TesseractBoss:cornersTell(dt, game, e, body)
    e.drive = { hold = true }
    self.spinWant = 0.12
    body.shake = 0.3
    if self.t > 0 then return end
    body.shake = 0
    local c = self.def.corners
    local cx, cy = body:centre(e.x, e.y)
    for i in pairs(body.hot) do
        local x, y = body:corner(i, e.x, e.y)
        local dx, dy = util.normalize(x - cx, y - cy)
        if dx == 0 and dy == 0 then dx = 1 end
        game.shots[#game.shots + 1] = {
            x = x, y = y, dx = dx, dy = dy,
            speed = c.speed * (c.slow + (1 - c.slow) * body:reachOf(i)),
            damage = scaled(e, c.damage), life = c.life,
            sprite = "vertex", radius = c.hit * e.reach, grow = e.grow,
        }
        game.particles:burst(x, y, 2, Palette.red)
    end
    Sfx.play("tick", 0.8)
    Camera.knock(1)
    body.hot = nil
    self.volleys = self.volleys - 1
    if self.volleys > 0 then
        -- Spun on a little and aimed again: the second volley comes out
        -- between the first.
        self.state, self.t = "cornersTurn", c.gap
    else
        self.spinWant = 1
        self:rest(e, pick(c.rest, self.phase))
    end
end

function TesseractBoss:cornersTurn(dt, game, e, body)
    e.drive = { hold = true }
    self.spinWant = 4
    if self.t <= 0 then
        body.hot = self:pickCorners(body)
        self.state, self.t = "cornersTell", self.def.corners.again
    end
end

--- the net --------------------------------------------------------------------

-- The cross of eight: a column of four out from where it hovers towards you,
-- and two arms either side of the second -- in (along, across) cells.
local CROSS = {
    { 0, 0 }, { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, -1 }, { 1, -2 }, { 2, 0 }, { 3, 0 },
}

function TesseractBoss:unfoldStart(game, e, body)
    local n = self.def.net
    local c = n.cell
    local p = game.player
    -- Towards you, on one of the page's four directions: a net is laid square
    -- on squared paper.
    local dx, dy = p.x - e.x, p.y - e.y
    if abs(dx) >= abs(dy) then dx, dy = dx >= 0 and 1 or -1, 0
    else dx, dy = 0, dy >= 0 and 1 or -1 end
    local rx, ry = snap(e.x, c), snap(e.y, c)

    local cells = {}
    for k, at in ipairs(CROSS) do
        local along, across = at[1], at[2]
        cells[k] = {
            x = rx + (along * dx - across * dy) * c,
            y = ry + (along * dy + across * dx) * c,
            -- How far it slides out from the root as the net opens.
            far = abs(along) + abs(across),
        }
    end
    -- The order the cubes go off in, by phase: root to tip, tip to root, or
    -- shuffled -- and the numbers drawn on them are that order.
    local order = {}
    for k = 1, #cells do order[k] = k end
    if self.phase == 2 then
        for k = 1, #cells do order[k] = #cells + 1 - k end
    elseif self.phase >= 3 then
        for k = #order, 2, -1 do
            local j = love.math.random(1, k)
            order[k], order[j] = order[j], order[k]
        end
    end
    for rank, k in ipairs(order) do cells[k].n = rank end

    self.net = {
        cells = cells, cell = c, rx = rx, ry = ry,
        age = 0, gone = 0,
        step = pick(n.step, self.phase),
        open = n.open, lead = n.lead, hot = n.hot, fold = n.fold,
        f = 0,
    }
    self.state, self.t = "unfold", 0
    Sfx.play("pin", 0.8)
end

-- When cube `n` (its number) goes off and when it stops.
local function cubeTimes(net, n)
    local from = net.open + net.lead + (n - 1) * net.step
    return from, from + net.hot
end

function TesseractBoss:unfold(dt, game, e, body)
    e.drive = { hold = true }
    local net = self.net
    net.age = net.age + dt
    self.spinWant = 2.2
    net.f = min(1, net.age / net.open)

    local p = game.player
    local last = 0
    local gone = 0
    for _, cell in ipairs(net.cells) do
        local from, to = cubeTimes(net, cell.n)
        last = max(last, to)
        local was = cell.stage
        if net.age >= to then
            cell.stage = "done"
        elseif net.age >= from then
            cell.stage = "hot"
        else
            cell.stage = nil
        end
        if cell.stage then gone = gone + 1 end
        if cell.stage == "hot" and was ~= "hot" then
            Camera.knock(1)
            Sfx.play("tick", 1 + cell.n * 0.06)
            game.particles:burst(cell.x + net.cell / 2, cell.y + net.cell / 2, 6, Palette.red)
        end
        if cell.stage == "hot" and p.x >= cell.x and p.x < cell.x + net.cell
            and p.y >= cell.y and p.y < cell.y + net.cell then
            if p:hurt(scaled(e, self.def.net.damage)) then
                game.particles:burst(p.x, p.y, 6, Palette.red)
            end
        end
    end
    net.gone = gone

    -- Folded back up into it once the last has gone off.
    if net.age >= last then
        net.folding = min(1, (net.age - last) / net.fold)
        if net.folding >= 1 then
            self.net = nil
            self.spinWant = 1
            game.particles:burst(e.x, e.y - 6, 10, Palette.red)
            self:rest(e, pick(self.def.net.rest, self.phase))
        end
    end
end

--- through the fourth dimension ----------------------------------------------

function TesseractBoss:foldStart(game, e, body)
    self.state, self.t = "foldOut", self.def.fold.out
    e.drive = { hold = true }
    Sfx.play("transition", 1.4)
end

-- Turning out of the page: smaller and faster until there is nothing of it
-- here, and nothing to hit.
function TesseractBoss:foldOut(dt, game, e, body)
    e.drive = { hold = true }
    local f = max(0, self.t) / self.def.fold.out
    body.fold = f * f
    self.spinWant = 1 + (1 - f) * 6
    e.hitCooldown = max(e.hitCooldown, 0.1)
    if self.t <= 0 then
        e.ghost = true
        body.fold, body.hidden = 0, true
        game.particles:burst(e.x, e.y - 6, 12, Palette.slate)
        local p = game.player
        local x, y = p.x, p.y
        if game.arena then x, y = game.arena:clamp(x, y, e.radius + 4) end
        self.mark = { x = x, y = y }
        self.state, self.t = "foldAim", pick(self.def.fold.aim, self.phase)
    end
end

function TesseractBoss:foldAim(dt, game, e, body)
    e.drive = { hold = true }
    e.hitCooldown = max(e.hitCooldown, 0.1)
    if self.t <= 0 then
        e.x, e.y = self.mark.x, self.mark.y
        body.hidden = false
        self.state, self.t = "foldIn", self.def.fold.back
    end
end

-- Back into the page, all at once, with a square going out from it.
function TesseractBoss:foldIn(dt, game, e, body)
    e.drive = { hold = true }
    e.hitCooldown = max(e.hitCooldown, 0.1)
    local f = 1 - max(0, self.t) / self.def.fold.back
    body.fold = f
    self.spinWant = 6 - f * 5
    if self.t <= 0 then
        body.fold, e.ghost = 1, false
        self.spinWant = 1
        local fd = self.def.fold
        local p = game.player
        local s = { x = e.x, y = e.y }
        if squareReach(s, p.x, p.y, body.yaw) < fd.shock and p:hurt(scaled(e, fd.damage)) then
            game.particles:burst(p.x, p.y, 6, Palette.red)
        end
        self.shock = { x = e.x, y = e.y, a = body.yaw }
        self.shockT = SHOCK_TIME
        self.mark = nil
        Camera.knock(4)
        Sfx.play("pin", 0.5)
        game.particles:burst(e.x, e.y, 24, Palette.red)
        for _ = 1, 10 do
            game.particles:crumb(e.x, e.y + e.radius, nil, nil, e.radius, Palette.graphite)
        end
        self:rest(e, pick(fd.rest, self.phase))
    end
end

--- going down -----------------------------------------------------------------

-- Down, it comes apart into its corners: a burst at every one of them, as if
-- the thirty-two edges had let go at once. Called by Game:killEnemy.
function TesseractBoss:dropParts(game)
    local e = self.e
    if not e or not e.tesseract then return end
    local body = e.tesseract
    for i = 1, #Tesseract.CORNERS do
        local x, y = body:corner(i, e.x, e.y)
        game.particles:burst(x, y, 4, i % 2 == 0 and Palette.red or Palette.ink)
    end
    Camera.knock(4)
end

--- drawing --------------------------------------------------------------------

-- A square `h` out from (x, y), turned by `a`: its four corners.
local function corners(x, y, h, a)
    local c, s = cos(a) * h, sin(a) * h
    return {
        x + c - s, y + s + c,
        x - c - s, y - s + c,
        x - c + s, y - s - c,
        x + c + s, y + s - c,
    }
end

-- A square's outline, whole or dashed (`dash` on, as many off, slid by `shift`).
local function square(x, y, h, a, dash, shift)
    local q = corners(x, y, h, a)
    for k = 1, 8, 2 do
        local m = k + 2 > 8 and 1 or k + 2
        local x0, y0, x1, y1 = q[k], q[k + 1], q[m], q[m + 1]
        if not dash then
            pixelart.line(x0, y0, x1, y1)
        else
            local len = util.len(x1 - x0, y1 - y0)
            for d = 0, floor(len) do
                if floor((d + (shift or 0)) / dash) % 2 == 0 then
                    local t = d / max(1, len)
                    love.graphics.rectangle("fill", floor(x0 + (x1 - x0) * t),
                        floor(y0 + (y1 - y0) * t), 1, 1)
                end
            end
        end
    end
end

-- The spans of whatever a pass sets off, filled in the colour set. Even-odd,
-- so a square with a square cut out of it is one path: round the outer, over
-- to the inner, round it, and back.
local function fillPass(s, kind, a)
    local function ring(h0, h1)
        local o, i = corners(s.x, s.y, h1, a), corners(s.x, s.y, h0, a)
        local poly = {}
        for k = 1, 8 do poly[k] = o[k] end
        poly[9], poly[10] = o[1], o[2]
        for k = 1, 8 do poly[10 + k] = i[k] end
        poly[19], poly[20] = i[1], i[2]
        return poly
    end
    local function fill(poly, h)
        pixelart.fillPolygon(poly, s.y - h * 1.5, s.y + h * 1.5, function(x, y, w)
            love.graphics.rectangle("fill", x, y, w, 1)
        end)
    end
    if kind == "band" then
        fill(ring(s.inner, s.outer), s.outer)
    else
        fill(corners(s.x, s.y, s.inner, a), s.inner)
        fill(ring(s.outer, s.outer + s.rim), s.outer + s.rim)
    end
end

-- A sprinkle of dots over what a pass will set off: the count-in, so which floor
-- is going is read off the floor and not worked out.
local function dotPass(s, kind, a, phase)
    local reach = s.outer + s.rim
    local step = 6
    for y = snap(s.y - reach * 1.42, step), s.y + reach * 1.42, step do
        for x = snap(s.x - reach * 1.42, step), s.x + reach * 1.42, step do
            local px, py = x + ((y / step + phase) % 2) * 3, y
            if inPass(s, kind, squareReach(s, px, py, a)) then
                love.graphics.rectangle("fill", floor(px), floor(py), 1, 1)
            end
        end
    end
end

-- A cube of the net: the square on the floor, and a second one up and to the
-- right joined at the corners, so the net reads as cubes laid out flat and not
-- as tiles.
local function cube(x, y, c, hot, colour)
    x, y = floor(x), floor(y)
    local d = max(2, floor(c / 7))
    if hot then
        love.graphics.setColor(Palette.red)
        love.graphics.rectangle("fill", x + 1, y + 1, c - 2, c - 2)
    end
    love.graphics.setColor(hot and Palette.ink or colour)
    local i0, i1 = x + 3, x + c - 4 - d
    local j0, j1 = y + 3 + d, y + c - 4
    local function rect(a0, b0, a1, b1)
        love.graphics.rectangle("fill", a0, b0, a1 - a0 + 1, 1)
        love.graphics.rectangle("fill", a0, b1, a1 - a0 + 1, 1)
        love.graphics.rectangle("fill", a0, b0, 1, b1 - b0 + 1)
        love.graphics.rectangle("fill", a1, b0, 1, b1 - b0 + 1)
    end
    rect(i0, j0, i1, j1)
    rect(i0 + d, j0 - d, i1 + d, j1 - d)
    for _, k in ipairs({ { i0, j0 }, { i1, j0 }, { i1, j1 } }) do
        pixelart.line(k[1], k[2], k[1] + d, k[2] - d)
    end
end

-- On the floor: the squares of an inside-out, the net, where it will come back
-- into the page, and the square shock of it coming back.
function TesseractBoss:drawGround(time)
    local e = self.e
    if not e then return end
    local on = floor(time * 10) % 2 == 0

    local s = self.flip
    if s then
        local kind = s.passes[s.pass]
        if self.state == "flipTell" then
            -- The squares turning the way they will, over and over, through
            -- the count-in; the floor that will go dotted.
            local a = s.a + s.turn * ((time * 1.5) % 1)
            love.graphics.setColor(on and Palette.red or Palette.blush)
            dotPass(s, kind, s.a, floor(time * 4))
            love.graphics.setColor(on and Palette.red or Palette.slate)
            square(s.x, s.y, s.inner, a, 3, time * 20)
            square(s.x, s.y, s.outer, a, 3, -time * 20)
            if kind == "inverse" then square(s.x, s.y, s.outer + s.rim, a, 2, time * 20) end
        elseif self.state == "flipHot" then
            local a = s.a + s.turn * s.f
            love.graphics.setColor(Palette.red)
            fillPass(s, kind, a)
            -- The two cubes passing through each other: the inner one going
            -- out and the outer one coming in.
            local g = s.f * s.f * (3 - 2 * s.f)
            love.graphics.setColor(Palette.ink)
            square(s.x, s.y, s.inner + (s.outer - s.inner) * g, a)
            square(s.x, s.y, s.outer - (s.outer - s.inner) * g, a)
        end
    end

    local net = self.net
    if net then
        local c = net.cell
        local open = net.f * net.f * (3 - 2 * net.f)
        local fold = net.folding or 0
        -- Which number is next to go: it blinks.
        local next
        for _, cell in ipairs(net.cells) do
            if not cell.stage and (not next or cell.n < next) then next = cell.n end
        end
        for _, cell in ipairs(net.cells) do
            -- Slid out from the root as it opens, and back in as it folds.
            local k = min(open, 1 - fold)
            local x = net.rx + (cell.x - net.rx) * k
            local y = net.ry + (cell.y - net.ry) * k
            local hot = cell.stage == "hot"
            local colour
            if cell.stage == "done" then
                colour = Palette.graphite
            elseif cell.n == next and on then
                colour = Palette.red
            else
                colour = Palette.slate
            end
            cube(x, y, c, hot, colour)
            if k > 0.9 and cell.stage ~= "done" then
                love.graphics.setColor(hot and Palette.paper or colour)
                local text = tostring(cell.n)
                Font.print(text, x + floor(c / 2) - floor(Font.width(text) / 2) - 1,
                    y + floor(c / 2) - 1)
            end
        end
    end

    if self.mark then
        local fd = self.def.fold
        local f = self.state == "foldAim" and 1 - max(0, self.t) / pick(fd.aim, self.phase) or 1
        love.graphics.setColor(on and Palette.red or Palette.slate)
        square(self.mark.x, self.mark.y, fd.shock, time * 1.2, 3, time * 20)
        love.graphics.setColor(Palette.graphite)
        square(self.mark.x, self.mark.y, max(1, fd.shock * (1 - f)), -time * 2)
    end
    if self.shockT > 0 and self.shock then
        love.graphics.setColor(Palette.red)
        local h = self.def.fold.shock * (1 - self.shockT / SHOCK_TIME) + 4
        square(self.shock.x, self.shock.y, h, self.shock.a)
        square(self.shock.x, self.shock.y, h * 0.6, self.shock.a + math.pi / 4)
    end
end

-- Over the crowd: nothing it does is in the air but the corners it throws,
-- which are ordinary shots (Sprites.vertex) the game draws.
function TesseractBoss:drawAir(time, e)
end

return TesseractBoss
