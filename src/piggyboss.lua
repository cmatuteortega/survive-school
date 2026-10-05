-- The piggy bank's mind: FINANCE's encore, and the fight in the book about
-- *greed*.
--
-- The stamp is a fight about which cell you are in. The piggy bank is the
-- thing the ledger was being kept for, and its fight is the one thing a ledger
-- cannot tell you: whether to go for the money. Everything it does puts coins
-- on the page, and the coins are real -- each one picked up is a coin in the
-- purse at the end of the run (`banked`, Game:runWorth) -- so every move is a
-- trade between what is lying there and what it costs to go and get it.
--
-- **It trots** at you, nose first, like anything else on four legs -- and it
-- turns to face where it is going, so where its snout is pointing is always
-- the next thing it is going to do.
--
-- **The charge.** It plants, digs in, and spits coins out of its slot into the
-- lane it is about to run down: bait, laid out between it and you. The lane is
-- drawn on the floor as a dashed red arrow and its rim blinks the wad's red,
-- and then it goes -- far faster than you, straight, off the walls of the box
-- -- and stands dizzy at the end of it, which is the window. Greed is picking up
-- the coins in the lane before it goes; safety is stepping out of the lane and
-- picking them up after. From the second phase it charges twice in a row.
--
-- **Savings.** Coins left lying are not yours yet. With enough of them on the
-- floor it rears up, nose in the air, every coin it means to have back blinks
-- red with a dashed line home -- and then they all slide back into its slot at
-- once, and anything they cross on the way is hit. So the coins you leave are
-- the next attack, and the coins you take are the ones that cannot be thrown
-- back at you: the cheapest way to dodge this move is to be greedy earlier.
--
-- **The shatter.** At under a third of its health the cracks that have been
-- spreading over its back (src/piggy.lua) give: it shakes, says so, and bursts,
-- and its savings come out of it as rings of coins going out across the box --
-- red while they are in the air and hurt like any shot, each ring with a gap in
-- it and turned from the last, so the way through is a zigzag. Every coin that
-- does not hit anybody lands where it stops and is a coin on the page: survive
-- it and you collect them. What is left of it is broken and has nothing left
-- to spit, and it charges three times over.
--
-- **Glue holds a tell.** A charge or a recall still being counted in is
-- dropped and it rests, as the eye's tells are -- the tool-shaped counterplay
-- every boss in the book has. Bait already spat stays where it landed.
--
-- The body is src/piggy.lua, painted every frame; this file moves it, throws
-- its coins and catches them, and reads where it is pointing. A coin lying on
-- the page is a pickup like a heart (`coin` in src/pickup.lua), so it outlives
-- the fight and is drawn and collected the way everything else on the floor is;
-- a coin in the air is this file's, until it lands.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Pickup = require("src.pickup")
local Piggy = require("src.piggy")
local pixelart = require("src.pixelart")
local util = require("src.util")

local PiggyBoss = {}
PiggyBoss.__index = PiggyBoss

-- The entrance: stood where it walked on, rattling its coins, for a beat.
local ENTER_TIME = 0.9

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

function PiggyBoss.new(def)
    return setmetatable({
        def = def.piggy,
        state = "enter", t = ENTER_TIME,
        phase = 1,
        last = nil,
        -- Coins in the air: spat as bait, called home, or burst out of it.
        flying = {},
        -- The coins on the floor a recall is calling home.
        called = nil,
        aim = nil, charges = 0, bounces = 0,
        e = nil,
    }, PiggyBoss)
end

function PiggyBoss:busy()
    return self.state ~= "idle"
end

--- the loop -------------------------------------------------------------------

function PiggyBoss:update(dt, game, e)
    self.e = e
    local body = e.piggy
    if dt <= 0 then return end

    local share = e.hp / e.maxHp
    body.hurt = 1 - share
    if self.phase == 1 and share <= self.def.second then self.phase = 2 end

    -- A third gone and more: it bursts. Only once it is free to, so a shatter
    -- never cuts a charge off half way down its lane.
    if not body.broken and share <= self.def.shatter.at
        and (self.state == "idle" or self.state == "resting") then
        self:calm(e)
        self.state, self.t = "crack", self.def.shatter.time
    end

    self:flights(dt, game, e)

    -- Glue answers a tell: a charge or a recall still being counted in is
    -- dropped, and it rests.
    if e.frozen > 0 and (self.state == "wind" or self.state == "rear") then
        self:calm(e)
        self:rest(e, 0.4)
    end

    self.t = self.t - dt
    self[self.state](self, dt, game, e)
    body:update(dt, e.x, e.y)
end

-- Everything a tell had going put back: its nose down, its rim still, the
-- coins it was calling left where they are.
function PiggyBoss:calm(e)
    local body = e.piggy
    body.pitchTo, body.shake = 0, 0
    e.chargePhase = nil
    self.aim, self.called, self.charges = nil, nil, 0
end

function PiggyBoss:rest(e, t)
    self.state, self.t = "resting", t
    e.drive = { hold = true }
end

function PiggyBoss:resting(dt, game, e)
    e.drive = { hold = true }
    if self.t <= 0 then
        e.piggy.shake = 0
        self.state = "idle"
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.6
    end
end

--- the entrance ---------------------------------------------------------------

function PiggyBoss:enter(dt, game, e)
    e.drive = { hold = true }
    e.piggy:face(game.player.x - e.x, game.player.y - e.y, math.huge)
    e.piggy.shake = self.t > 0.3 and 0.6 or 0
    if self.t <= 0 then
        e.piggy.shake = 0
        self.state, self.t = "idle", 0.8
    end
end

--- trotting about -------------------------------------------------------------

-- At you, facing the way it is going: the walk is Enemy:update's chase, and
-- the heading it leaves is where its nose goes.
function PiggyBoss:idle(dt, game, e)
    e.drive = nil
    local hx, hy = e.headX, e.headY
    if hx == 0 and hy == 0 then hx, hy = game.player.x - e.x, game.player.y - e.y end
    e.piggy:face(hx, hy, 5)
    if self.t <= 0 and e.frozen <= 0 then self:choose(game, e) end
end

-- How many coins are lying on the floor of the box for it to call home.
local function lying(game)
    local list = {}
    for _, p in ipairs(game.pickups) do
        if p.kind == "coin" and not p.dead
            and (not game.arena or game.arena:contains(p.x, p.y)) then
            list[#list + 1] = p
        end
    end
    return list
end

-- A charge, mostly; a recall when there is enough out there to be worth one,
-- likelier the more there is. Never after a recall, since the floor it would
-- recall from is the one it has just emptied. Broken, it only charges.
function PiggyBoss:choose(game, e)
    local r = self.def.recall
    local coins = #lying(game)
    local w = { charge = 1.2, recall = 0 }
    if not e.piggy.broken and coins >= r.least and self.last ~= "recall" then
        w.recall = 0.6 + coins * 0.12
    end
    if self.last == "charge" then w.charge = w.charge * 0.6 end
    local move = love.math.random() * (w.charge + w.recall) < w.charge and "charge" or "recall"
    self.last = move
    self[move .. "Start"](self, game, e)
end

--- the charge -----------------------------------------------------------------

function PiggyBoss:chargeStart(game, e)
    self.charges = pick(self.def.charge.count, self.phase)
    self:windStart(game, e, true)
end

-- Plant, aim and dig in. The aim is locked here and never looked at again --
-- the wad's rule (Enemy:charge), and what makes it a lane you can step out of.
-- The first wind of a run of charges spits its bait; the later ones are quick.
function PiggyBoss:windStart(game, e, first)
    local c = self.def.charge
    local p = game.player
    local dx, dy = util.normalize(p.x - e.x, p.y - e.y)
    if dx == 0 and dy == 0 then dx, dy = 1, 0 end
    self.aim = { dx = dx, dy = dy }
    self.bounces = 0
    self.state = "wind"
    self.t = first and pick(c.wind, self.phase) or c.again
    self.windTime = self.t
    e.piggy:face(dx, dy, 12)
    e.piggy.pitchTo = -0.18

    -- The bait: `bait` coins spat out over the wind, landing down the lane at
    -- even steps from `near` out, as far as the box lets them.
    self.spit = {}
    local n = first and not e.piggy.broken and pick(c.bait, self.phase) or 0
    for k = 1, n do
        local d = c.near + (k - 1) * c.step + (love.math.random() - 0.5) * 6
        local tx, ty = e.x + dx * d, e.y + dy * d
        if game.arena then tx, ty = game.arena:clamp(tx, ty, 8) end
        self.spit[k] = { x = tx, y = ty, at = self.t * (1 - k / (n + 1)) }
    end
end

function PiggyBoss:wind(dt, game, e)
    e.drive = { hold = true }
    -- The wad's own blinking rim (Enemy:outlineColour), borrowed rather than
    -- copied: the one red warning the game already teaches.
    e.chargePhase, e.phaseT = "wind", math.max(0, self.t)
    e.piggy.shake = 0.5
    for _, s in ipairs(self.spit) do
        if not s.done and self.t <= s.at then
            s.done = true
            local sx, sy = e.piggy:slot(e.x, e.y)
            self:throw(game, sx, sy, s.x, s.y, self.def.coin.arc)
        end
    end
    if self.t <= 0 then
        local aim = self.aim
        self.aim, self.spit = nil, nil
        self.dash = { dx = aim.dx, dy = aim.dy }
        self.state, self.t = "charge", self.def.charge.time
        self.stall, self.lastX = 0, nil
        e.piggy.shake = 0
        Camera.knock(1)
    end
end

-- Down the lane and off the walls of the box. Read off where the clamp left it
-- last frame (Game:updateEnemies clamps after the move), so a bounce is the box
-- saying no rather than this guessing where the box is -- the eye's bowl, at a
-- pig's speed.
function PiggyBoss:charge(dt, game, e)
    local c, dash = self.def.charge, self.dash
    e.chargePhase = "dash"

    local box = game.arena
    local hit = false
    if box then
        local pad = e.radius + 0.5
        if dash.dx < 0 and e.x <= box.left + pad then dash.dx, hit = -dash.dx, true end
        if dash.dx > 0 and e.x >= box:right() - pad then dash.dx, hit = -dash.dx, true end
        if dash.dy < 0 and e.y <= box.top + pad then dash.dy, hit = -dash.dy, true end
        if dash.dy > 0 and e.y >= box:bottom() - pad then dash.dy, hit = -dash.dy, true end
    end
    -- A pen line stops it dead: there is nothing to bounce off.
    if self.lastX and util.len(e.x - self.lastX, e.y - self.lastY) < c.speed * dt * 0.25 then
        self.stall = self.stall + 1
    else
        self.stall = 0
    end
    self.lastX, self.lastY = e.x, e.y

    if hit then
        self.bounces = self.bounces + 1
        Camera.knock(2)
        game.particles:burst(e.x, e.y, 8, Palette.graphite)
    end
    if (hit and self.bounces > pick(c.bounces, self.phase)) or self.stall >= 4 or self.t <= 0 then
        self.dash, self.lastX = nil, nil
        e.chargePhase = nil
        e.piggy.pitchTo = 0
        self.charges = self.charges - 1
        if self.charges > 0 and e.frozen <= 0 then
            self:windStart(game, e, false)
        else
            -- Dizzy at the end of it: the window.
            e.piggy.shake = 0.4
            self:rest(e, pick(c.rest, self.phase))
        end
        return
    end

    e.drive = { dash = true, dx = dash.dx, dy = dash.dy, speed = c.speed }
    e.piggy:face(dash.dx, dash.dy, math.huge)
end

--- savings --------------------------------------------------------------------

-- Nose in the air, and every coin on the floor of the box is called home.
-- Fixed here, so a coin picked up during the tell is a coin it does not get.
function PiggyBoss:recallStart(game, e)
    self.called = lying(game)
    self.state, self.t = "rear", pick(self.def.recall.tell, self.phase)
    e.drive = { hold = true }
    e.piggy.pitchTo = 0.45
end

function PiggyBoss:rear(dt, game, e)
    e.drive = { hold = true }
    e.piggy.shake = 0.3
    if self.t > 0 then return end
    local r = self.def.recall
    local sx, sy = e.x, e.y - 8
    for _, p in ipairs(self.called) do
        if not p.dead then
            p.dead = true
            local dx, dy, d = util.normalize(sx - p.x, sy - p.y)
            self.flying[#self.flying + 1] = {
                kind = "home", x = p.x, y = p.y, dx = dx, dy = dy,
                left = d, speed = pick(r.speed, self.phase),
                damage = scaled(e, r.damage),
            }
        end
    end
    self.called = nil
    self.state, self.t = "recall", r.hold
end

-- Stood with its nose up while they come in; the coins are flights() to move.
function PiggyBoss:recall(dt, game, e)
    e.drive = { hold = true }
    e.piggy.shake = 0
    local home = false
    for _, f in ipairs(self.flying) do
        if f.kind == "home" then home = true break end
    end
    if not home or self.t <= 0 then
        e.piggy.pitchTo = 0
        self:rest(e, pick(self.def.recall.rest, self.phase))
    end
end

--- the shatter ----------------------------------------------------------------

-- Shaking harder and harder, then in pieces.
function PiggyBoss:crack(dt, game, e)
    local s = self.def.shatter
    e.drive = { hold = true }
    local k = 1 - math.max(0, self.t) / s.time
    e.piggy.shake = 0.5 + k * 1.5
    if self.t <= 0 then
        e.piggy.shake = 0
        e.piggy.broken = true
        self.phase = 3
        game:say("BANKRUPT!")
        game.particles:burst(e.x, e.y - 8, 30, Palette.blush)
        game.particles:burst(e.x, e.y - 8, 16, Palette.ink)
        Camera.knock(4)
        self.volleys, self.volleyT = s.volleys, 0
        self.gapA = love.math.random() * math.pi * 2
        self.state, self.t = "burst", 0
    end
end

-- `volleys` rings of `count` coins out of it, `gap` seconds apart, each with a
-- hole `hole` coins wide and turned half a step from the last.
function PiggyBoss:burst(dt, game, e)
    local s = self.def.shatter
    e.drive = { hold = true }
    self.volleyT = self.volleyT - dt
    if self.volleys > 0 and self.volleyT <= 0 then
        self.volleyT = s.gap
        self.volleys = self.volleys - 1
        local n = s.count
        local step = math.pi * 2 / n
        local turn = (s.volleys - self.volleys) * step * 0.5
        local hole = love.math.random(0, n - 1)
        for k = 0, n - 1 do
            if (k - hole) % n >= s.hole then
                local a = self.gapA + turn + k * step
                self.flying[#self.flying + 1] = {
                    kind = "burst", x = e.x, y = e.y - 4,
                    dx = math.cos(a), dy = math.sin(a), speed = s.speed,
                    left = s.near + love.math.random() * (s.far - s.near),
                    damage = scaled(e, s.damage),
                }
            end
        end
        Camera.knock(1)
    end
    if self.volleys <= 0 and self.volleyT <= 0 then
        self:rest(e, s.rest)
    end
end

--- coins in the air -------------------------------------------------------------

-- A coin lobbed from (x, y) to land at (tx, ty) as a pickup: the bait.
function PiggyBoss:throw(game, x, y, tx, ty, arc)
    self.flying[#self.flying + 1] = {
        kind = "lob", x = x, y = y, fx = x, fy = y, tx = tx, ty = ty,
        t = 0, time = arc.time, high = arc.high,
    }
end

-- A coin down on the page, inside the box, where it can be picked up.
local function land(game, x, y)
    if game.arena then x, y = game.arena:clamp(x, y, 6) end
    game.pickups[#game.pickups + 1] = Pickup.new("coin", x, y)
end

-- Every coin in the air, one step. A lob lands; a coin called home goes in at
-- the slot; a burst coin flies out and lands. The two that hurt hurt through
-- Player:hurt like everything else, and a coin that hits you is spent.
function PiggyBoss:flights(dt, game, e)
    local player = game.player
    for i = #self.flying, 1, -1 do
        local f = self.flying[i]
        local done = false
        if f.kind == "lob" then
            f.t = f.t + dt
            local k = math.min(1, f.t / f.time)
            f.x = f.fx + (f.tx - f.fx) * k
            f.y = f.fy + (f.ty - f.fy) * k
            f.z = f.high * 4 * k * (1 - k)
            if k >= 1 then
                land(game, f.tx, f.ty)
                done = true
            end
        else
            -- Home coins chase the slot as it moves; burst coins go straight.
            if f.kind == "home" then
                local dx, dy, d = util.normalize(e.x - f.x, e.y - 8 - f.y)
                f.dx, f.dy, f.left = dx, dy, d
            end
            local step = math.min(f.left, f.speed * dt)
            f.x, f.y = f.x + f.dx * step, f.y + f.dy * step
            f.left = f.left - step
            if util.len(player.x - f.x, player.y - f.y) < player.radius + self.def.coin.hit then
                if player:hurt(f.damage) then
                    game.particles:burst(player.x, player.y, 6, Palette.red)
                end
                done = true
            elseif f.left <= 0.5 then
                if f.kind == "burst" then
                    land(game, f.x, f.y)
                else
                    game.particles:burst(f.x, f.y, 3, Palette.blush)
                end
                done = true
            end
        end
        if done then table.remove(self.flying, i) end
    end
end

-- Down, its coins come down with it: whatever is in the air lands where it is,
-- and the last of its savings spill out round it -- harmless now, and the
-- fight's last offer. Called by Game:killEnemy.
function PiggyBoss:dropParts(game)
    local e = self.e
    for _, f in ipairs(self.flying) do
        land(game, f.tx or f.x, f.ty or f.y)
    end
    self.flying = {}
    if not e then return end
    for k = 1, self.def.spill do
        local a = k / self.def.spill * math.pi * 2 + love.math.random() * 0.5
        local d = 18 + love.math.random() * 22
        land(game, e.x + math.cos(a) * d, e.y + math.sin(a) * d)
    end
    game.particles:burst(e.x, e.y - 8, 40, Palette.blush)
    game.particles:burst(e.x, e.y - 8, 20, Palette.red)
    Camera.knock(4)
end

--- drawing --------------------------------------------------------------------

local function dashes(x0, y0, dx, dy, len, phase, on)
    on = on or 3
    for i = 0, math.floor(len) do
        if math.floor((i - phase) / on) % 2 == 0 then
            love.graphics.rectangle("fill", math.floor(x0 + dx * i), math.floor(y0 + dy * i), 1, 1)
        end
    end
end

-- On the floor: the lane a charge is about to take, as a dashed red arrow, and
-- every coin a recall is calling home, blinking with its line back to the slot.
function PiggyBoss:drawGround(time)
    local e = self.e
    if not e then return end
    local aim = self.aim
    if aim then
        love.graphics.setColor(Palette.red)
        local len = self.def.charge.tell
        local x0, y0 = e.x + aim.dx * (e.radius + 4), e.y + aim.dy * (e.radius + 4)
        dashes(x0, y0, aim.dx, aim.dy, len, time * 30, 4)
        local tx, ty = x0 + aim.dx * len, y0 + aim.dy * len
        local a = math.atan2(aim.dy, aim.dx)
        for _, side in ipairs({ -1, 1 }) do
            local b = a + math.pi * 0.8 * side
            pixelart.line(math.floor(tx), math.floor(ty),
                math.floor(tx + math.cos(b) * 6), math.floor(ty + math.sin(b) * 6))
        end
    end
    if self.called then
        local on = math.floor(time * 10) % 2 == 0
        for _, p in ipairs(self.called) do
            if not p.dead then
                love.graphics.setColor(on and Palette.red or Palette.blush)
                pixelart.circleOutline(math.floor(p.x), math.floor(p.y), 7)
                local dx, dy, d = util.normalize(e.x - p.x, e.y - 8 - p.y)
                dashes(p.x, p.y, dx, dy, d, time * 30, 2)
            end
        end
    end
end

-- Over the crowd: every coin in the air -- the bait on its arc with its shadow
-- under it, and the ones that hurt in red.
function PiggyBoss:drawAir(time, e)
    for _, f in ipairs(self.flying) do
        if f.kind == "lob" then
            Piggy.coinShadow(f.x, f.y)
            Piggy.coin(f.x, f.y - (f.z or 0), false)
        else
            Piggy.coin(f.x, f.y, true)
        end
    end
end

return PiggyBoss
