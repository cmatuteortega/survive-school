-- The red pen's mind: GRAMMAR's encore, and the fight in the book about
-- *corrections*.
--
-- The dictionary is where the words come from, and its fight is about lines --
-- where words go. The red pen is what happens to them once they are written:
-- they are circled, crossed out and graded. It is a teacher's click pen, far
-- longer than the page is tall (src/redpen.lua), held by a hand somewhere off the
-- top of the screen, and it writes on the page you are standing on. Everything it
-- puts down is red ink, and red ink is wet before it is dry: wet, it hurts to
-- cross; dry, it is only a record of what it thought of you.
--
-- **It writes at you.** Between moves the nib comes across the page in a cursive
-- scrawl -- loops, a prolate cycloid, the "eeee" every hand writes when it is
-- not spelling anything -- and the scrawl is ink. Kite it round in circles and
-- the page fills up with its handwriting. Every couple of seconds it flicks a
-- blot at you, so standing off is not free either.
--
--  - **WRONG.** It rings you. A dashed circle is drawn round where you are and
--    follows you while the pen lifts and hops to the near side of it; then the
--    nib runs round it, and when the ring closes everything inside is marked
--    wrong -- you, and any of the crowd caught in there with you. The ring it
--    draws is wet, so the way out is the gap ahead of the nib, before it closes,
--    or straight across the ink and take the smaller hit. At the last third it
--    rings you twice, the second ring tighter.
--  - **The strike-through.** The body is the move. It teeters back off its nib,
--    a strip as long as it is is marked across the page from its foot through
--    where you are -- following you, then locked and blinking -- and it falls,
--    the whole length of it, flat across the box. Under it is a hit; the crowd
--    under it is flattened. It bounces, rattles, and lies there, which is the
--    window, and leaves a red line through the page where it fell. From the
--    second third it rolls a little way towards you before it gets up -- watch
--    the clip go round -- and at the last third it falls twice.
--  - **The shake.** A pen that will not write gets shaken. It whips its top back
--    and forth across the screen, faster and wider, spitting specks off the
--    nib, and then flicks: a fan of blots lobbed round you that land as pools of
--    ink. Two flicks at the last third.
--  - **The grade.** From the second third: an F, a hundred pixels tall, written
--    over where you are standing -- every stroke shown before it is written, the
--    one about to go blinking, the middle bar through you. The strokes are thick
--    and wet. At the last third it circles the F when it is done.
--
-- **Glue clicks it shut.** The tip goes back in with a click, and a pen with its
-- tip in cannot write: anything it was about to do or was half way through doing
-- is dropped, the ring left open, the letter left unfinished. A pen already
-- falling still falls -- glue does not argue with gravity -- and one lying down
-- stays down until it comes free.
--
-- **It is long, so it can be hit long.** The pen is the boss as much as its nib
-- is, so all of it you can see is stood for by bodies on the page (`penpart` in
-- src/enemy.lua, the still life's stand-in) that every weapon finds and hurts,
-- and whatever they take comes off the boss. The nib is the real body and the
-- one that hurts to walk into; the barrel above it is up in the air.
--
-- The body is src/redpen.lua, painted every frame; this file moves it, clicks
-- it, and owns all the ink: the scrawl, the rings, the strike-throughs and the
-- grades, and which of them are still wet.

local Palette = require("src.palette")
local Camera = require("src.camera")
local Puddle = require("src.puddle")
local RedPen = require("src.redpen")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local PenBoss = {}
PenBoss.__index = PenBoss

local TAU = math.pi * 2
local floor, abs, max, min, cos, sin, sqrt = math.floor, math.abs, math.max, math.min, math.cos, math.sin, math.sqrt

local NIBY, R = RedPen.NIBY, RedPen.R

-- The entrance: stood up in the page where it landed, it clicks itself ready
-- -- out, in, out -- and leans over to write.
local ENTER_TIME = 1.3
local CLICKS = { 0.22, 0.36, 0.5 }

-- How it is held to write: leaning back from the nib by `LEAN` radians, its top
-- towards `AZ` on the page -- up the screen and a little right, a right hand.
local LEAN, AZ = 0.42, -math.pi / 2 + 0.35

-- How fast a fall goes: the angular pull of gravity on a thing this long,
-- radians a second a second at lying flat. Half a second from teetering to flat.
local PULL = 22

-- The bodies that stand for the barrel: how many, from how far up it, how far
-- apart, and how wide each is.
local PARTS, PART_FROM, PART_STEP, PART_R = 8, 30, 28, 9

-- How long the mark of a ring closing, and a slam's shock, are drawn.
local FLASH_TIME, SHOCK_TIME = 0.4, 0.35

-- The most ink on the page at once: the oldest goes first.
local INK_MOST = 900

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

local function scaled(e, damage) return damage * e.damage / e.def.damage end

-- The writing lean as a direction, nib to button.
local function writeAxis()
    return sin(LEAN) * cos(AZ), sin(LEAN) * sin(AZ), cos(LEAN)
end

-- Leaning `th` from upright towards (ax, ay): a fall's axis.
local function planeAxis(ax, ay, th)
    return sin(th) * ax, sin(th) * ay, cos(th)
end

-- How high the nib has to be for the barrel to rest on the page, at `th` from
-- upright: nothing stood up, the barrel's own radius flat.
local function restLift(th)
    return max(0, R * sin(th) - (RedPen.TIP + 12) * cos(th))
end

-- A hit on one of the crowd from inside the pen's own turn, which is inside a
-- walk of the horde: never the last of its health. Killing it here would take it
-- out of the list under the walk's feet (the reason Game:updateRams is a pass
-- of its own); left on one, the next thing of yours to touch it finishes it.
local function mark(o, damage)
    local take = min(damage, o.hp - 1)
    if take > 0 then o:hurt(take) end
    -- Glue deepens a cut (Enemy:hurt), so the floor is put back after it.
    if o.hp < 1 then o.hp = 1 end
end

local function ease(k)
    k = min(1, max(0, k))
    return k * k * (3 - 2 * k)
end

function PenBoss.new(def)
    return setmetatable({
        def = def.redpen,
        state = "enter", t = ENTER_TIME,
        phase = 1,
        last = nil, before = nil,
        ink = {},       -- every line it has put down, wet and dry
        flashes = {},   -- rings that have just closed
        shocks = {},    -- slams going out from a fallen pen
        pen = nil,      -- where a move's line last got to
        trail = nil,    -- and where the scrawl last put ink
        base = nil, dir = nil, wt = 0,
        flickT = 1.5, twirlT = 2.5, twirl = 0, nerveT = 1.5, unclick = nil,
        vx = 0, vy = 0, lx = nil, ly = nil,
        tipWant = 0, clicked = 0,
        circle = nil, fall = nil, shake = nil, grade = nil,
        parts = nil,
        glued = false,
        clock = 0,
        e = nil,
    }, PenBoss)
end

function PenBoss:busy()
    return self.state ~= "idle"
end

--- the nib ----------------------------------------------------------------------

-- Where the nib's foot is on the page: below e, which is the middle of the hit
-- circle round the nib and the grip.
local function nib(e)
    return e.x, e.y + NIBY
end

-- And put there, inside the box.
function PenBoss:put(game, e, x, y)
    if game.arena then x, y = game.arena:clamp(x, y, 4) end
    e.x, e.y = x, y - NIBY
    return x, y
end

-- Held to write, the top lagging behind where the nib is going.
function PenBoss:writePose(body, dt, rate)
    local x, y, h = writeAxis()
    -- Dragged, never thrown over: the lag is capped, so a nib running round a
    -- ring leans into it rather than lying down.
    local sx, sy = self.vx * 0.004, self.vy * 0.004
    local m = util.len(sx, sy)
    if m > 0.35 then sx, sy = sx * 0.35 / m, sy * 0.35 / m end
    body:ease(x - sx, y - sy, h, dt * (rate or 8))
end

--- ink --------------------------------------------------------------------------

-- A line of ink from a to b, `w` wide, wet for `wet` seconds and hurting
-- `damage` while it is, then dry for `dry`. `fresh` keeps a dry line red for a
-- moment anyway, for a mark that is a record and not a hazard.
function PenBoss:line(ax, ay, bx, by, w, wet, dry, damage, fresh)
    local ink = self.ink
    ink[#ink + 1] = { ax = ax, ay = ay, bx = bx, by = by, w = w, age = 0,
                      wet = wet, life = wet + dry, damage = damage, fresh = fresh or 0,
                      seed = love.math.random() }
    if #ink > INK_MOST then table.remove(ink, 1) end
end

-- Ink dries and goes; ink still wet hurts whoever is standing in it.
function PenBoss:inkUpdate(dt, game, e)
    local p = game.player
    local hit = false
    for i = #self.ink, 1, -1 do
        local l = self.ink[i]
        l.age = l.age + dt
        if l.age >= l.life then
            table.remove(self.ink, i)
        elseif not hit and l.age < l.wet and l.damage > 0 then
            local d = util.distToSegment(p.x, p.y, l.ax, l.ay, l.bx, l.by)
            if d < l.w * 0.5 + p.radius * 0.5 + 0.5 then
                hit = true
                if p:hurt(l.damage) then
                    game.particles:burst(p.x, p.y, 6, Palette.red)
                end
            end
        end
    end

    for i = #self.flashes, 1, -1 do
        local f = self.flashes[i]
        f.t = f.t + dt
        if f.t >= FLASH_TIME then table.remove(self.flashes, i) end
    end
    for i = #self.shocks, 1, -1 do
        local s = self.shocks[i]
        s.t = s.t + dt
        if s.t >= SHOCK_TIME then table.remove(self.shocks, i) end
    end
end

-- The scrawl: while it is writing at you, wherever the nib goes on the page is
-- ink. Kept apart from `pen`, which is where a move's own line last got to.
function PenBoss:scrawl(e, body)
    local def = self.def.trail
    local x, y = nib(e)
    if self.state ~= "idle" or self.glued or body.lift > 1 or body.tip < 0.6 then
        self.trail = nil
        return
    end
    local at = self.trail
    if not at then
        self.trail = { x = x, y = y }
    elseif util.len(x - at.x, y - at.y) >= def.step then
        self:line(at.x, at.y, x, y, 1, def.wet, def.dry, scaled(e, def.damage))
        at.x, at.y = x, y
    end
end

-- A blot lobbed from the nib to land `dist` away along `a`, where it is a pool
-- of ink (src/puddle.lua): the eye's tear, in red ink.
function PenBoss:blot(game, e, a, dist, spec)
    local x, y = nib(e)
    local life = dist / spec.speed
    game.shots[#game.shots + 1] = {
        x = x, y = y - 4, dx = cos(a), dy = sin(a),
        speed = spec.speed, damage = scaled(e, spec.damage),
        life = life, flight = life, arc = spec.high, drop = "red",
        radius = 3 * e.reach, grow = e.grow,
        wet = spec.puddle, wetDamage = scaled(e, spec.puddle.damage), wetReach = e.reach,
    }
end

--- the loop ---------------------------------------------------------------------

function PenBoss:update(dt, game, e)
    self.e, self.game = e, game
    local body = e.redpen
    if dt <= 0 then return end

    -- Killed through the barrel. A stand-in never answers that it died -- the
    -- barrel is not what dies -- so the pen notices for itself, on its own turn,
    -- which is a place in the frame a kill is safe to make (the still life's way).
    if e.hp <= 0 then
        e.hitCooldown = 1
        game:killEnemyAt(e)
        return
    end

    self.clock = self.clock + dt

    -- The phase, at the eye's thirds, and said out loud.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        game:say(phase >= 3 and "SEE ME!" or "RED INK!")
        local x, y = nib(e)
        game.particles:burst(x, y - 8, phase >= 3 and 30 or 16, Palette.red)
        Camera.knock(phase >= 3 and 4 or 2)
        Sfx.play("accept", 0.6 + phase * 0.12)
        -- And it clicks about it.
        self.nerveT = 0
    end

    self:standIns(game, e)

    -- Glue clicks it shut. Whatever it was about to do, or was half way through
    -- writing, is dropped; a fall is let finish.
    local glued = e.frozen > 0
    if glued and not self.glued then
        local s = self.state
        if s ~= "falling" and s ~= "lying" and s ~= "rolling" and s ~= "rising" then
            if s ~= "idle" and s ~= "resting" and s ~= "enter" then game:say("CLICK!") end
            self.circle, self.shake, self.grade = nil, nil, nil
            if s ~= "enter" then self:rest(e, 0.5) end
        end
        Sfx.play("tick", 0.7)
    elseif not glued and self.glued then
        Sfx.play("tick", 1.5)
    end
    self.glued = glued

    -- The tip, clicked towards where it is wanted: quickly, a click is a click.
    local want = glued and 0 or self.tipWant
    if body.tip < want then body.tip = min(want, body.tip + dt * 12)
    elseif body.tip > want then body.tip = max(want, body.tip - dt * 12) end

    -- Stuck, it holds whatever it is doing -- stood up, or lying where it fell
    -- -- except a fall, which finishes.
    e.drive = { hold = true }
    local down = self.state == "lying" or self.state == "rolling" or self.state == "rising"
    if not glued or self.state == "falling" then
        self.t = self.t - dt
        self[self.state](self, dt, game, e, body)
    elseif not down then
        self:writePose(body, dt, 4)
        body.lift = max(0, body.lift - dt * 30)
        body.shake = 0
    end

    -- How fast the nib went, for the lean and the recoil.
    local x, y = nib(e)
    if self.lx then
        local k = min(1, dt * 10)
        self.vx = self.vx + ((x - self.lx) / dt - self.vx) * k
        self.vy = self.vy + ((y - self.ly) / dt - self.vy) * k
    end
    self.lx, self.ly = x, y
    if abs(self.vx) + abs(self.vy) > 1 then e.headX, e.headY = util.normalize(self.vx, self.vy) end

    self:scrawl(e, body)
    self:inkUpdate(dt, game, e)
    self:syncParts(game, e, body, dt)
    body:update(dt)
end

function PenBoss:rest(e, t)
    self.state, self.t = "resting", t
end

function PenBoss:resting(dt, game, e, body)
    self:writePose(body, dt, 5)
    body.lift = max(0, body.lift - dt * 30)
    body.shake = 0
    if self.t <= 0 then
        self:write(game, e)
        self.t = pick(self.def.cool, self.phase) + love.math.random() * 0.5
    end
end

--- the barrel's stand-ins ---------------------------------------------------------

-- Bodies on the page for the barrel (the still life's stand-in, src/stilllife.lua).
-- Put in once and moved every frame from inside the boss's own turn, which is
-- safe wherever the draw's depth sort has left them in the horde; taking them
-- out is not, and waits for the wreck (`sweep`).
function PenBoss:standIns(game, e)
    if self.parts then return end
    local Enemy = require("src.enemy")
    self.parts = {}
    for k = 1, PARTS do
        local part = Enemy.new("penpart", e.x, e.y)
        part.stand = e
        part.ghost = true
        game.enemies[#game.enemies + 1] = part
        self.parts[k] = part
    end
end

-- Along the barrel as it is drawn, and off the page outside the box or while the
-- pen is not there to be hit. Never hurting anyone: the barrel is up in the air.
--
-- A hit on any of them lights the whole pen, but only a blink of blush and only
-- now and then: the barrel is most of what a weapon can reach, and a pen lit on
-- every one of a volley's hits would be a pale pink stick for the whole fight.
local BLINK, BLINK_EVERY = 0.04, 0.22

function PenBoss:syncParts(game, e, body, dt)
    if not self.parts then return end
    local ox, oy = body:origin(e.x, e.y)
    local box = game.arena
    self.blinkT = max(0, (self.blinkT or 0) - dt)
    for k, part in ipairs(self.parts) do
        local sx, sy = body:screenAt(PART_FROM + (k - 1) * PART_STEP)
        part.x, part.y = ox + sx, oy + sy
        part.radius = PART_R
        part.ghost = e.ghost or (box and not box:contains(part.x, part.y)) or false
        part.hitCooldown = 1
        if part.flash > 0 and self.blinkT <= 0 and e.flash <= 0 then
            e.flash, self.blinkT = BLINK, BLINK_EVERY
        end
    end
end

--- the entrance -----------------------------------------------------------------

-- Stood up in the page where it landed, tip in. Click, click, click -- and it
-- leans over to write.
function PenBoss:enter(dt, game, e, body)
    local f = 1 - max(0, self.t) / ENTER_TIME
    body:point(0.02, -0.04, 1)
    for k, at in ipairs(CLICKS) do
        if f >= at and self.clicked < k then
            self.clicked = k
            self.tipWant = k % 2 == 1 and 1 or 0
            Sfx.play("tick", 1.4 + k * 0.15)
            Camera.knock(1)
            local x, y = nib(e)
            game.particles:burst(x, y - 2, 4, k == #CLICKS and Palette.red or Palette.slate)
        end
    end
    if f > 0.62 then
        local k = ease((f - 0.62) / 0.38)
        local x, y, h = writeAxis()
        body:point(0.02 + (x - 0.02) * k, -0.04 + (y + 0.04) * k, 1 + (h - 1) * k)
    end
    if self.t <= 0 then
        self.clicked = 0
        self.tipWant = 1
        Sfx.play("stapler", 1.2)
        local x, y = nib(e)
        -- The first mark: a dot of ink where it stood.
        game.particles:burst(x, y, 10, Palette.red)
        self:line(x - 1, y, x + 1, y, 3, 0, 2.5, 0, 1)
        self:write(game, e)
        self.t = 0.8
    end
end

--- writing at you -----------------------------------------------------------------

-- The loop of the scrawl at phase `wt` going along (dx, dy): back and up from
-- the line it is moving along, so the loops stand above the line like a hand's.
function PenBoss:loopAt(dx, dy, wt)
    local r = self.def.write.loop
    return -dx * r * sin(wt) + dy * r * cos(wt), -dy * r * sin(wt) - dx * r * cos(wt)
end

-- Back to writing, from wherever the nib is: the line it writes along is put
-- under the nib, so the scrawl starts where the pen is rather than jumping.
function PenBoss:write(game, e)
    local x, y = nib(e)
    local p = game.player
    local dx, dy = util.normalize(p.x - x, p.y - y)
    if dx == 0 and dy == 0 then dx, dy = 1, 0 end
    self.dir = { dx, dy }
    local ox, oy = self:loopAt(dx, dy, self.wt)
    self.base = { x = x - ox, y = y - oy }
    self.state = "idle"
    self.tipWant = 1
end

function PenBoss:idle(dt, game, e, body)
    local def = self.def
    local w = def.write
    local p = game.player
    local base = self.base

    -- Which way the line goes: round towards you, but not on the spot, so a
    -- player circling it gets a curve of loops and not a knot.
    local tx, ty, d = util.normalize(p.x - base.x, p.y - base.y)
    local dx, dy = self.dir[1], self.dir[2]
    if d > 0 then
        local turn = math.atan2(dx * ty - dy * tx, dx * tx + dy * ty)
        local most = 2.2 * dt
        turn = max(-most, min(most, turn))
        local c, s = cos(turn), sin(turn)
        dx, dy = dx * c - dy * s, dx * s + dy * c
        self.dir[1], self.dir[2] = dx, dy
    end
    if d > w.near then
        local v = pick(w.speed, self.phase)
        base.x, base.y = base.x + dx * v * dt, base.y + dy * v * dt
    end
    if game.arena then base.x, base.y = game.arena:clamp(base.x, base.y, 10) end

    self.wt = self.wt + dt * w.spin
    local ox, oy = self:loopAt(dx, dy, self.wt)
    self:put(game, e, base.x + ox, base.y + oy)
    body.lift = max(0, body.lift - dt * 30)
    body.shake = 0
    self:writePose(body, dt)

    -- Twiddled in its fingers now and then: a turn about its own length, the
    -- clip and the print going round.
    self.twirlT = self.twirlT - dt
    if self.twirlT <= 0 then
        self.twirlT = 2.5 + love.math.random() * 2.5
        self.twirl = TAU
        Sfx.play("tick", 0.6)
    end
    if self.twirl > 0 then
        local step = min(self.twirl, dt * 11)
        self.twirl = self.twirl - step
        body.roll = body.roll + step
    end

    -- And clicked, nervously: once in a while, and all the time at the last third.
    self.nerveT = self.nerveT - dt
    if self.nerveT <= 0 then
        self.nerveT = self.phase >= 3 and 0.9 + love.math.random() * 0.6
            or 3 + love.math.random() * 3
        self.tipWant = 0
        self.unclick = 0.09
        Sfx.play("tick", 1.6)
    end
    if self.unclick then
        self.unclick = self.unclick - dt
        if self.unclick <= 0 then
            self.unclick = nil
            self.tipWant = 1
            Sfx.play("tick", 1.8)
        end
    end

    -- A blot flicked at you every so often: the least of what it does.
    self.flickT = self.flickT - dt
    if self.flickT <= 0 then
        local fl = def.flick
        self.flickT = pick(fl.every, self.phase)
        local x, y = nib(e)
        local a = math.atan2(p.y - y, p.x - x)
        local dist = util.clamp(util.len(p.x - x, p.y - y), 24, 150)
        self:blot(game, e, a, dist, fl)
        Sfx.play("pin", 1.5)
    end

    if self.t <= 0 then self:choose(game, e) end
end

-- The ring for someone near; the fall for someone it can reach a pen's length
-- off; the shake either way; the grade from the second third. The last move is
-- marked down, the one before a little.
function PenBoss:choose(game, e)
    local def = self.def
    local x, y = nib(e)
    local d = util.len(game.player.x - x, game.player.y - y)
    local w = {
        circle = d < 140 and 1.4 or 0.9,
        fall = d > 50 and 1.3 or 0.7,
        shake = 1.0,
    }
    if self.phase >= def.grade.from then w.grade = 1.1 end
    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.2 end
    if self.before and w[self.before] then w[self.before] = w[self.before] * 0.6 end
    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "shake"
    for _, name in ipairs({ "circle", "fall", "shake", "grade" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.before, self.last = self.last, move
    self.pen = nil
    -- Whatever nervous click it was in the middle of, the tip is out to work.
    self.tipWant, self.unclick = 1, nil
    self[move .. "Start"](self, game, e)
end

--- WRONG ------------------------------------------------------------------------

-- A ring round (x, y), or round you and following you while the pen gets to it.
function PenBoss:circleStart(game, e, x, y, r, loops)
    local c = self.def.circle
    local p = game.player
    self.circle = {
        x = x or p.x, y = y or p.y, follow = x == nil,
        r = r or pick(c.radius, self.phase),
        loops = loops or pick(c.loops, self.phase),
        sign = love.math.random() < 0.5 and -1 or 1,
        a = 0, a0 = 0,
    }
    self.state, self.t = "circleAim", pick(c.aim, self.phase)
    Sfx.play("tick", 1.2)
end

-- Where on the ring the nib goes in: the near side, from where the pen is.
function PenBoss:circleIn(e)
    local c = self.circle
    local x, y = nib(e)
    local a = math.atan2(y - c.y, x - c.x)
    return a, c.x + cos(a) * c.r, c.y + sin(a) * c.r
end

function PenBoss:circleAim(dt, game, e, body)
    local c = self.circle
    local p = game.player
    if c.follow then
        local k = min(1, dt * 10)
        c.x, c.y = c.x + (p.x - c.x) * k, c.y + (p.y - c.y) * k
    end
    -- Lifted and carried to the ring.
    local a, sx, sy = self:circleIn(e)
    local x, y = nib(e)
    local k = min(1, dt * 9)
    self:put(game, e, x + (sx - x) * k, y + (sy - y) * k)
    body.lift = min(10, body.lift + dt * 60)
    self:writePose(body, dt, 10)
    if self.t <= 0 then
        c.a0, c.a = a, 0
        c.follow = false
        self:put(game, e, sx, sy)
        body.lift = 0
        self.pen = { x = sx, y = sy }
        self.state = "circleDraw"
        local lap = pick(self.def.circle.lap, self.phase) * (c.r / pick(self.def.circle.radius, 1))
        c.lap = lap
        local name, pitch = Sfx.brushFor(lap)
        Sfx.play(name, pitch)
        Camera.knock(1)
        game.particles:burst(sx, sy, 5, Palette.red)
    end
end

function PenBoss:circleDraw(dt, game, e, body)
    local def = self.def.circle
    local c = self.circle
    e.hitCooldown = max(e.hitCooldown, 0.1)
    c.a = min(TAU, c.a + dt * TAU / c.lap)
    local ang = c.a0 + c.sign * c.a
    local x, y = c.x + cos(ang) * c.r, c.y + sin(ang) * c.r
    local pen = self.pen
    if pen then
        self:line(pen.x, pen.y, x, y, 2, def.wet, def.dry, scaled(e, def.line))
    end
    self.pen = { x = x, y = y }
    self:put(game, e, x, y)
    self:writePose(body, dt, 14)
    if love.math.random() < dt * 30 then
        game.particles:burst(x, y, 1, Palette.red)
    end
    if c.a >= TAU then self:circleShut(game, e) end
end

-- Shut: everything inside it is marked wrong.
function PenBoss:circleShut(game, e)
    local def = self.def.circle
    local c = self.circle
    local p = game.player
    if util.len(p.x - c.x, p.y - c.y) < c.r - 1 then
        if p:hurt(scaled(e, def.damage)) then
            game.particles:burst(p.x, p.y, 10, Palette.red)
        end
    end
    game:eachWithin(c.x, c.y, c.r, function(o)
        if o ~= e and not o.def.boss and o.hp > 0 then
            mark(o, def.crowd)
            game.particles:burst(o.x, o.y, 4, Palette.red)
        end
    end)
    self.flashes[#self.flashes + 1] = { x = c.x, y = c.y, r = c.r, t = 0 }
    game:say("WRONG!")
    Camera.knock(5)
    Sfx.play("stamp", 1.15)
    for k = 1, 16 do
        local a = k / 16 * TAU
        game.particles:crumb(c.x + cos(a) * c.r, c.y + sin(a) * c.r, cos(a), sin(a), 3, Palette.red)
    end
    self.pen = nil
    local left = c.loops - 1
    if left > 0 then
        self:circleStart(game, e, nil, nil, c.r * 0.72, left)
        self.t = self.t * def.again
    else
        self.circle = nil
        self:rest(e, pick(def.rest, self.phase))
    end
end

--- the strike-through -----------------------------------------------------------

function PenBoss:fallStart(game, e)
    self.fall = { left = pick(self.def.fall.falls, self.phase) }
    self:fallAim(game, e, pick(self.def.fall.tell, self.phase))
end

function PenBoss:fallAim(game, e, tell)
    local f = self.fall
    local p = game.player
    local x, y = nib(e)
    f.ax, f.ay = util.normalize(p.x - x, p.y - y)
    if f.ax == 0 and f.ay == 0 then f.ax, f.ay = 0, 1 end
    f.tell, f.locked, f.slammed, f.rolled = tell, false, false, false
    f.th, f.w, f.bounces = 0, 0, 0
    self.state, self.t = "fallTell", tell
    Sfx.play("tick", 0.6)
end

-- Teetering back off its nib, the strip it is going to fall along following you
-- -- and then locked, blinking, and it rocks.
function PenBoss:fallTell(dt, game, e, body)
    local f = self.fall
    local def = self.def.fall
    if not f.locked then
        local x, y = nib(e)
        local p = game.player
        local tx, ty = util.normalize(p.x - x, p.y - y)
        if tx ~= 0 or ty ~= 0 then
            local turn = math.atan2(f.ax * ty - f.ay * tx, f.ax * tx + f.ay * ty)
            local most = 3 * dt
            turn = max(-most, min(most, turn))
            local c, s = cos(turn), sin(turn)
            f.ax, f.ay = f.ax * c - f.ay * s, f.ax * s + f.ay * c
        end
        if self.t <= f.tell * (1 - def.lock) then
            f.locked = true
            Sfx.play("tick", 0.9)
            Camera.knock(1)
        end
    end
    local th = -0.16 + (f.locked and 0.06 * sin(self.clock * 22) or 0.02 * sin(self.clock * 9))
    local x, y, h = planeAxis(f.ax, f.ay, th)
    body:ease(x, y, h, dt * 7)
    body.lift = max(0, body.lift - dt * 30)
    body.shake = f.locked and 0.6 or 0
    if self.t <= 0 then
        local U = body.U
        f.th = math.atan2(U[1] * f.ax + U[2] * f.ay, U[3])
        f.w = 0.4
        body.shake = 0
        self.state = "falling"
        Sfx.play("ruler", 0.45)
    end
end

function PenBoss:falling(dt, game, e, body)
    local f = self.fall
    f.w = f.w + PULL * sin(max(f.th, 0.06)) * dt
    f.th = f.th + f.w * dt
    if f.th >= math.pi / 2 then
        f.th = math.pi / 2
        if not f.slammed then
            f.slammed = true
            self:slam(game, e, body)
            f.w = -f.w * 0.2
        else
            f.bounces = f.bounces + 1
            if f.bounces >= 2 or abs(f.w) < 0.6 then
                f.w = 0
                self.state, self.t = "lying", pick(self.def.fall.lie, self.phase)
            else
                f.w = -f.w * 0.35
                Camera.knock(1)
                Sfx.play("stamp", 1.5)
            end
        end
    end
    body:point(planeAxis(f.ax, f.ay, f.th))
    body.lift = restLift(f.th)
end

-- Where it lies on the page: from the nib's foot along the fall, as long as it is.
function PenBoss:lyingLine(e, body)
    local f = self.fall
    local x, y = nib(e)
    local L = body:reach()
    return x, y, x + f.ax * L, y + f.ay * L
end

-- Flat on the page: whatever is under it is hit, the crowd under it flattened,
-- the page shaken, and a red line left through where it fell.
function PenBoss:slam(game, e, body)
    local def = self.def.fall
    local p = game.player
    local x0, y0, x1, y1 = self:lyingLine(e, body)
    if util.distToSegment(p.x, p.y, x0, y0, x1, y1) < R + p.radius * 0.6 + 1 then
        if p:hurt(scaled(e, def.damage)) then
            game.particles:burst(p.x, p.y, 10, Palette.red)
        end
    end
    local f = self.fall
    local mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    game:eachWithin(mx, my, util.len(x1 - x0, y1 - y0) / 2 + 12, function(o)
        if o ~= e and not o.def.boss and o.hp > 0
            and util.distToSegment(o.x, o.y, x0, y0, x1, y1) < R + o.radius then
            mark(o, def.crowd)
            local side = (o.x - x0) * -f.ay + (o.y - y0) * f.ax >= 0 and 1 or -1
            o:knockback(-f.ay * side, f.ax * side, 200)
        end
    end)
    Camera.knock(7)
    Sfx.play("stamp", 0.55)
    Sfx.play("ruler", 0.6)
    local L = util.len(x1 - x0, y1 - y0)
    for s = 0, L, 9 do
        local px, py = x0 + f.ax * s, y0 + f.ay * s
        game.particles:crumb(px, py, f.ax, f.ay, R, Palette.graphite)
    end
    game.particles:burst(x0, y0, 14, Palette.red)
    self.shocks[#self.shocks + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, nx = -f.ay, ny = f.ax, t = 0 }
    -- The strike-through: red for a moment and then the blush of dry ink. A
    -- record, not a hazard -- you were under it or you were not.
    self:line(x0, y0, x1, y1, 2, 0, 4.5, 0, 0.6)
end

-- Lying where it fell: the window. From the second third it rolls a little way
-- towards you first.
function PenBoss:lying(dt, game, e, body)
    local f = self.fall
    local def = self.def.fall
    body:point(planeAxis(f.ax, f.ay, math.pi / 2))
    body.lift = restLift(math.pi / 2)
    local roll = pick(def.roll, self.phase)
    if roll > 0 and not f.rolled and self.t <= pick(def.lie, self.phase) * 0.5 then
        f.rolled = true
        local p = game.player
        local x, y = nib(e)
        local side = (p.x - x) * -f.ay + (p.y - y) * f.ax >= 0 and 1 or -1
        f.rx, f.ry, f.rollLeft, f.rollHit = -f.ay * side, f.ax * side, roll, false
        f.rollSign = side
        self.state = "rolling"
        Sfx.play("ruler", 0.7)
        return
    end
    if self.t <= 0 then
        self.state, self.t = "rising", self.def.fall.rise
        Sfx.play("tick", 0.5)
    end
end

-- Rolling across the page, the clip going round, flattening what it rolls over.
function PenBoss:rolling(dt, game, e, body)
    local f = self.fall
    local def = self.def.fall
    local step = min(def.rollSpeed * dt, f.rollLeft)
    local x, y = nib(e)
    local nx, ny = self:put(game, e, x + f.rx * step, y + f.ry * step)
    local moved = util.len(nx - x, ny - y)
    f.rollLeft = f.rollLeft - step
    body.roll = body.roll + moved / R * f.rollSign
    body:point(planeAxis(f.ax, f.ay, math.pi / 2))

    local p = game.player
    local x0, y0, x1, y1 = self:lyingLine(e, body)
    if not f.rollHit and util.distToSegment(p.x, p.y, x0, y0, x1, y1) < R + p.radius * 0.6 then
        f.rollHit = true
        if p:hurt(scaled(e, def.rollDamage)) then
            game.particles:burst(p.x, p.y, 8, Palette.red)
        end
    end
    game:eachWithin((x0 + x1) / 2, (y0 + y1) / 2, util.len(x1 - x0, y1 - y0) / 2 + 12, function(o)
        if o ~= e and not o.def.boss and util.distToSegment(o.x, o.y, x0, y0, x1, y1) < R + o.radius then
            o:knockback(f.rx, f.ry, 160)
        end
    end)
    if love.math.random() < dt * 25 then
        local s = love.math.random() * util.len(x1 - x0, y1 - y0)
        game.particles:crumb(x0 + f.ax * s, y0 + f.ay * s, f.rx, f.ry, 3, Palette.graphite)
    end
    if f.rollLeft <= 0 or moved < step * 0.3 then
        self.state, self.t = "lying", 0.25
    end
end

-- Pushed back up on its nib, slowly: the end of the window.
function PenBoss:rising(dt, game, e, body)
    local f = self.fall
    local def = self.def.fall
    local k = ease(1 - max(0, self.t) / def.rise)
    local px, py, ph = planeAxis(f.ax, f.ay, math.pi / 2)
    local wx, wy, wh = writeAxis()
    body:point(px + (wx - px) * k, py + (wy - py) * k, ph + (wh - ph) * k)
    body.lift = restLift(math.pi / 2) * (1 - k)
    if self.t <= 0 then
        body.lift = 0
        f.left = f.left - 1
        if f.left > 0 then
            self:fallAim(game, e, pick(self.def.fall.tell, self.phase) * self.def.fall.again)
        else
            self.fall = nil
            self:rest(e, pick(def.rest, self.phase))
        end
    end
end

--- the shake ----------------------------------------------------------------------

function PenBoss:shakeStart(game, e)
    local s = self.def.shake
    self.shake = { volleys = pick(s.volleys, self.phase), tell = pick(s.tell, self.phase),
                   side = 1 }
    self.state, self.t = "shakeTell", self.shake.tell
    Sfx.play("tick", 1.3)
end

-- Its top whipped back and forth across the screen, wider and wider, specks off
-- the nib -- then the flick.
function PenBoss:shakeTell(dt, game, e, body)
    local sh = self.shake
    local p = game.player
    local x, y = nib(e)
    local dx, dy = util.normalize(p.x - x, p.y - y)
    if dx == 0 and dy == 0 then dx, dy = 0, 1 end
    local k = 1 - max(0, self.t) / sh.tell
    local amp = 0.25 + 0.55 * k
    local a = amp * sin(self.clock * TAU * 4)
    local side = a >= 0 and 1 or -1
    if side ~= sh.side then
        sh.side = side
        Sfx.play("tick", 0.7 + k * 0.5)
    end
    -- Whipped side to side across the screen, whichever way you are -- a pen
    -- whipped towards you and away only gets longer and shorter -- leaning back
    -- the way it writes.
    local wx, wy = writeAxis()
    body:ease(sin(a) + wx * 0.4, wy * 0.4, cos(a), dt * 25)
    body.lift = min(3, body.lift + dt * 20)
    body.shake = 0.3 + k * 0.6
    if love.math.random() < dt * (10 + k * 30) then
        game.particles:burst(x, y - 2, 1, Palette.red)
    end
    if self.t <= 0 then self:flick(game, e, body, dx, dy) end
end

-- The flick: a fan of blots lobbed round you, and the pen jerked at you.
function PenBoss:flick(game, e, body, dx, dy)
    local s = self.def.shake
    local sh = self.shake
    local p = game.player
    local x, y = nib(e)
    local n = pick(s.blots, self.phase)
    local at = math.atan2(dy, dx)
    local d = util.len(p.x - x, p.y - y)
    -- Every other volley shifted half a gap, so the gap you stood in is where
    -- the next blot goes.
    local shift = sh.volleys % 2 == 0 and 0.5 or 0
    for k = 1, n do
        local a = at + (k - (n + 1) / 2 + shift) * 0.34 + (love.math.random() - 0.5) * 0.08
        local dist = util.clamp(d + (love.math.random() - 0.5) * 50, s.near, s.far)
        self:blot(game, e, a, dist, s)
    end
    body:point(dx * 0.7, dy * 0.7, 0.7)
    body.shake = 0
    Camera.knock(2)
    Sfx.play("pin", 0.9)
    game.particles:burst(x, y - 2, 8, Palette.red)
    sh.volleys = sh.volleys - 1
    if sh.volleys > 0 then
        self.t = s.gap
        sh.tell = s.gap
    else
        self.shake = nil
        self:rest(e, pick(s.rest, self.phase))
    end
end

--- the grade ----------------------------------------------------------------------

-- An F over where you are standing, the middle bar through you.
function PenBoss:gradeStart(game, e)
    local g = self.def.grade
    local p = game.player
    local tall, wide = g.tall, g.wide
    local left, top = p.x - wide * 0.4, p.y - tall * 0.48
    local box = game.arena
    if box then
        left = util.clamp(left, box.left + 8, box:right() - 8 - wide)
        top = util.clamp(top, box.top + 8, box:bottom() - 8 - tall)
    end
    local mid = top + tall * 0.48
    self.grade = {
        strokes = {
            { left, top, left, top + tall },
            { left, top, left + wide, top },
            { left, mid, left + wide * 0.8, mid },
        },
        k = 1, s = 0, hop = nil,
        cx = left + wide / 2, cy = top + tall / 2, size = max(tall, wide),
    }
    self.state, self.t = "gradeTell", pick(g.rear, self.phase)
    Sfx.play("tick", 1.0)
end

function PenBoss:gradeTell(dt, game, e, body)
    local st = self.grade.strokes[1]
    local x, y = nib(e)
    local k = min(1, dt * 6)
    self:put(game, e, x + (st[1] - x) * k, y + (st[2] - y) * k)
    body.lift = min(10, body.lift + dt * 60)
    self:writePose(body, dt, 10)
    if self.t <= 0 then
        self:put(game, e, st[1], st[2])
        body.lift = 0
        self:strokeGo(game, e)
    end
end

function PenBoss:strokeGo(game, e)
    local g = self.grade
    local st = g.strokes[g.k]
    g.s = 0
    g.len = util.len(st[3] - st[1], st[4] - st[2])
    self.pen = { x = st[1], y = st[2] }
    self.state = "gradeDraw"
    local name, pitch = Sfx.brushFor(g.len / pick(self.def.grade.speed, self.phase))
    Sfx.play(name, pitch)
    Camera.knock(1)
end

function PenBoss:gradeDraw(dt, game, e, body)
    local def = self.def.grade
    local g = self.grade
    e.hitCooldown = max(e.hitCooldown, 0.1)

    -- Between strokes: lifted and carried to the start of the next.
    if g.hop then
        local h = g.hop
        h.t = h.t + dt
        local k = min(1, h.t / def.hop)
        local x, y = h.x0 + (h.x1 - h.x0) * k, h.y0 + (h.y1 - h.y0) * k
        self:put(game, e, x, y)
        body.lift = 10 * sin(k * math.pi)
        self:writePose(body, dt, 12)
        if k >= 1 then
            g.hop = nil
            body.lift = 0
            self:strokeGo(game, e)
        end
        return
    end

    local st = g.strokes[g.k]
    g.s = min(g.len, g.s + pick(def.speed, self.phase) * dt)
    local f = g.len > 0 and g.s / g.len or 1
    local x, y = st[1] + (st[3] - st[1]) * f, st[2] + (st[4] - st[2]) * f
    local pen = self.pen
    if pen then
        self:line(pen.x, pen.y, x, y, def.width, def.wet, def.dry, scaled(e, def.damage))
    end
    self.pen = { x = x, y = y }
    self:put(game, e, x, y)
    body.lift = 0
    self:writePose(body, dt, 14)
    if love.math.random() < dt * 40 then game.particles:burst(x, y, 1, Palette.red) end

    if g.s >= g.len then
        Camera.knock(2)
        Sfx.play("stapler", 1.3)
        game.particles:burst(x, y, 6, Palette.red)
        self.pen = nil
        g.k = g.k + 1
        local nxt = g.strokes[g.k]
        if nxt then
            g.hop = { t = 0, x0 = x, y0 = y, x1 = nxt[1], y1 = nxt[2] }
        else
            -- Done. At the last third it is circled.
            self.grade = nil
            if self.phase >= def.circle then
                self:circleStart(game, e, g.cx, g.cy, g.size * 0.62, 1)
            else
                self:rest(e, pick(def.rest, self.phase))
            end
        end
    end
end

--- going down ---------------------------------------------------------------------

-- Down: its stand-ins stop being hit, the ink still wet dries where it is, and
-- what was left in it runs out of the nib onto the page -- a pool that hurts
-- nobody. Called by Game:killEnemy, which can be inside a walk of the horde, so
-- the stand-ins are only ghosted here and taken off the page by `sweep`.
function PenBoss:dropParts(game)
    for _, part in ipairs(self.parts or {}) do part.ghost = true end
    for _, l in ipairs(self.ink) do l.wet = 0 end
    self.circle, self.shake, self.grade = nil, nil, nil
    local e = self.e
    if not e or not e.redpen then return end
    e.redpen.tip = 0
    e.redpen.dirty = true
    local x, y = nib(e)
    game.puddles[#game.puddles + 1] = Puddle.new(x, y,
        { radius = 15, life = 9, drops = 10 }, 0, love.math.random(2 ^ 20))
    game.particles:burst(x, y, 30, Palette.red)
end

-- And off the page, from the wreck's first frame (src/wreck.lua): after every
-- walk of the horde has finished, where taking them out shifts nothing.
function PenBoss:sweep(game)
    for _, part in ipairs(self.parts or {}) do
        part.gone = true
        for i = #game.enemies, 1, -1 do
            if game.enemies[i] == part then
                table.remove(game.enemies, i)
                break
            end
        end
    end
    self.parts = nil
end

--- drawing ------------------------------------------------------------------------

-- A dashed line, `on` pixels on and off, crawling with `phase`.
local function dashes(x0, y0, x1, y1, phase, on)
    local dx, dy, len = util.normalize(x1 - x0, y1 - y0)
    on = on or 3
    for i = 0, floor(len) do
        if floor((i - phase) / on) % 2 == 0 then
            love.graphics.rectangle("fill", floor(x0 + dx * i), floor(y0 + dy * i), 1, 1)
        end
    end
end

-- A dotted ring, or the arc of it from `a0` going `span` (signed) round.
local function dotted(x, y, r, phase, a0, span)
    a0, span = a0 or 0, span or TAU
    local n = floor(abs(span) * r / 3) + 1
    for k = 0, n do
        local a = a0 + span * (k + (phase % 1)) / (n + 1)
        love.graphics.rectangle("fill", floor(x + cos(a) * r), floor(y + sin(a) * r), 1, 1)
    end
end

-- One line of ink: red wet, blush dry, dropping out a segment at a time at the
-- end of its life rather than fading -- no alpha on this page.
local function drawInk(l)
    local left = l.life - l.age
    if left < 0.8 and l.seed > left / 0.8 then return end
    love.graphics.setColor((l.age < l.wet or l.age < l.fresh) and Palette.red or Palette.blush)
    if l.w <= 1 then
        pixelart.line(floor(l.ax), floor(l.ay), floor(l.bx), floor(l.by))
    else
        pixelart.band(l.ax, l.ay, l.bx, l.by, l.w)
        if l.w >= 3 then
            pixelart.circleFill(l.bx, l.by, floor(l.w / 2))
        end
    end
end

-- Its shadow, thrown by the lamp (src/redpen.lua): down and right off every
-- point of it by its height -- so the nib's is under the nib and the top's is a
-- long way off across the page -- a band dithered in graphite, the way a
-- pencil shades, and no wider than the pen.
local SHADOW_X, SHADOW_Y = 0.72, 0.46

function PenBoss:drawShadow(e)
    local body = e.redpen
    local ox, oy = nib(e)
    local L = body:reach()
    local x0, y0, h0 = body:along(0)
    local x1, y1, h1 = body:along(L)
    local ax, ay = ox + x0 + h0 * SHADOW_X, oy + y0 + h0 * SHADOW_Y
    local bx, by = ox + x1 + h1 * SHADOW_X, oy + y1 + h1 * SHADOW_Y
    local dx, dy, len = util.normalize(bx - ax, by - ay)
    love.graphics.setColor(Palette.graphite)
    if len < 2 then
        pixelart.circleFill(ax, ay, 4)
        return
    end
    -- Only what is on the screen: the far end of it is often a long way off.
    local left, top, w, h = Camera.bounds()
    local seen = {}
    for s = 0, floor(len) do
        local cx, cy = ax + dx * s, ay + dy * s
        if cx > left - 8 and cx < left + w + 8 and cy > top - 8 and cy < top + h + 8 then
            -- Narrower at the nib, where the pen is.
            local half = s < 12 and 1 + s / 6 or 3
            for o = -half, half do
                local px, py = floor(cx - dy * o + 0.5), floor(cy + dx * o + 0.5)
                local key = px * 65536 + py
                if (px + py) % 2 == 0 and not seen[key] then
                    seen[key] = true
                    love.graphics.rectangle("fill", px, py, 1, 1)
                end
            end
        end
    end
end

-- On the page: the shadow, the ink, and every tell -- the ring to be drawn, the
-- strip it will fall along, the strokes of the grade.
function PenBoss:drawGround(time)
    local e = self.e
    if not e or not e.redpen then return end

    if self.state ~= "enter" or e.redpen.tip > 0 then self:drawShadow(e) end
    for _, l in ipairs(self.ink) do drawInk(l) end

    local blink = floor(time * 10) % 2 == 0

    -- The ring: dotted all the way round while it is aimed, then the part still
    -- to be drawn, blinking, ahead of the nib.
    local c = self.circle
    if c then
        if self.state == "circleAim" then
            love.graphics.setColor(Palette.blush)
            dotted(c.x, c.y, c.r, time * 2)
            love.graphics.setColor(blink and Palette.red or Palette.blush)
            dotted(c.x, c.y, c.r - 4, -time * 3, 0, TAU)
        elseif self.state == "circleDraw" then
            love.graphics.setColor(blink and Palette.red or Palette.blush)
            local at = c.a0 + c.sign * c.a
            dotted(c.x, c.y, c.r, time * 4, at, c.sign * (TAU - c.a))
        end
    end

    for _, f in ipairs(self.flashes) do
        local k = f.t / FLASH_TIME
        if k < 0.2 then
            love.graphics.setColor(Palette.red)
            pixelart.circleFill(f.x, f.y, floor(f.r))
        else
            love.graphics.setColor(k < 0.6 and Palette.red or Palette.blush)
            pixelart.circleOutline(f.x, f.y, floor(f.r + (k - 0.2) * 24))
            -- And a big cross through it: wrong.
            local s = f.r * 0.5
            pixelart.band(f.x - s, f.y - s, f.x + s, f.y + s, 3)
            pixelart.band(f.x - s, f.y + s, f.x + s, f.y - s, 3)
        end
    end

    -- The strip it will fall along: both edges dashed, crawling out from the nib,
    -- and hatched across once it is locked.
    local f = self.fall
    if f and self.state == "fallTell" then
        local x0, y0 = nib(e)
        local L = e.redpen:reach()
        local nx, ny = -f.ay, f.ax
        local w = R + 3
        love.graphics.setColor(f.locked and (blink and Palette.red or Palette.blush) or Palette.red)
        for _, side in ipairs({ -1, 1 }) do
            dashes(x0 + nx * w * side, y0 + ny * w * side,
                x0 + nx * w * side + f.ax * L, y0 + ny * w * side + f.ay * L, -time * 30, 4)
        end
        local ex, ey = x0 + f.ax * L, y0 + f.ay * L
        dashes(ex - nx * w, ey - ny * w, ex + nx * w, ey + ny * w, 0, 2)
        if f.locked then
            for s = 6, L, 10 do
                local px, py = x0 + f.ax * s, y0 + f.ay * s
                pixelart.line(floor(px - nx * w + f.ax * 4), floor(py - ny * w + f.ay * 4),
                    floor(px + nx * w - f.ax * 4), floor(py + ny * w - f.ay * 4))
            end
        end
    end

    -- Where it will roll: the far edge of the ground it is about to cover.
    if f and self.state == "lying" and not f.rolled and pick(self.def.fall.roll, self.phase) > 0 then
        local x0, y0 = nib(e)
        local L = e.redpen:reach()
        local p = self.game and self.game.player
        local side = 1
        if p then side = (p.x - x0) * -f.ay + (p.y - y0) * f.ax >= 0 and 1 or -1 end
        local d = pick(self.def.fall.roll, self.phase) + R
        local nx, ny = -f.ay * side, f.ax * side
        love.graphics.setColor(blink and Palette.red or Palette.blush)
        dashes(x0 + nx * d, y0 + ny * d, x0 + nx * d + f.ax * L, y0 + ny * d + f.ay * L, -time * 30, 3)
    end

    for _, s in ipairs(self.shocks) do
        local k = s.t / SHOCK_TIME
        local d = R + 2 + k * 26
        love.graphics.setColor(k < 0.5 and Palette.slate or Palette.graphite)
        for _, side in ipairs({ -1, 1 }) do
            pixelart.line(floor(s.x0 + s.nx * d * side), floor(s.y0 + s.ny * d * side),
                floor(s.x1 + s.nx * d * side), floor(s.y1 + s.ny * d * side))
        end
    end

    -- The grade's strokes: every one still to be written dashed in blush, the
    -- next blinking red.
    local g = self.grade
    if g then
        for k = g.k, #g.strokes do
            local st = g.strokes[k]
            local next = k == g.k and not (self.state == "gradeDraw" and not g.hop)
            love.graphics.setColor(next and (blink and Palette.red or Palette.blush) or Palette.blush)
            for _, off in ipairs({ -2, 2 }) do
                local dx, dy = util.normalize(st[3] - st[1], st[4] - st[2])
                dashes(st[1] - dy * off, st[2] + dx * off, st[3] - dy * off, st[4] + dx * off,
                    -time * 24, 3)
            end
        end
    end
end

-- Over the crowd: nothing it lets go of flies but the blots, which are the
-- game's own shots; a ring closing is shouted on the page.
function PenBoss:drawAir(time, e)
end

return PenBoss
