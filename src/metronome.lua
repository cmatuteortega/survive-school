-- The MUSIC boss's mind and its pendulum: a metronome, and the one fight in the
-- book about *time*.
--
-- The eye is a fight about the ground and the whistle about what is in the air.
-- This one is about when. Everything it does lands on its own tick, the tick is
-- the sound it makes and the arm you can see swinging, and the answer to every
-- move is to read the beat and move between them. MUSIC is the page whose drills
-- all arrive on the beat (src/subjects.lua), and this is the thing keeping it.
--
-- **The clock.** It counts in beats rather than seconds, at a tempo set by how
-- far the fight has got -- 60, then 80, then 100 a minute at the same two
-- thirds and one third the eye turns at -- and four beats to the bar. The arm
-- reaches the end of its swing exactly on each beat, so a beat can be *seen*
-- coming as well as heard. Everything below is scheduled on that count, and
-- every move starts on a downbeat after a full bar of count-in, so the tell is
-- always one bar long and always at the tempo the move will be played at.
--
--  - **It walks on the beat.** It hops for the first half of each beat and
--    stands for the rest, so even its walk is a rhythm you can see. It roams
--    rather than chases: it circles you at a middle distance -- the distance
--    its sweep wants -- and every few bars changes which way round it goes.
--    It walks between moves, in the rest after one, and while its scale
--    marches, and plants itself only for the two moves drawn round its own
--    body, the sweep and the chord. On every other beat between moves it
--    throws a note at you, so standing still is never free.
--  - **The sweep.** It plants itself facing you and the arm becomes a beam
--    across the floor, swinging the fan in front of it in time with the
--    pendulum. The count-in draws the fan and a ghost of the beam already
--    swinging; then it is hot for a bar, two at the last third. The beam is far
--    quicker across the fan than you are, so the answer is to be out of the fan
--    -- round the back of it, which is also where the damage goes in.
--  - **The chord.** Rings round it, drawn on the floor for the count-in, then
--    struck one a beat from the inside out, each blinking red on the beat
--    before it goes. There is room to stand between them, and the room *inside*
--    a ring that has just gone is room again -- so the answer is to step in
--    across a ring the moment after it is struck. Three rings, four at the last
--    third.
--  - **The scale.** A wall of notes along one edge of the box, with a hole in
--    it: for the count-in it sits there, and then it marches across the box one
--    step a beat while the hole climbs one note a beat along it -- a scale run
--    up the staves. The answer is to walk with the hole, which at the last
--    third is climbing at a hundred notes a minute.
--
-- **Glue stops the clock.** A glued metronome is a stopped one: no beat, no
-- swing, nothing it is half way through moves on, and a count-in it was in the
-- middle of is dropped -- which is the one tool-shaped answer this fight has,
-- and the one that makes the most sense for it.
--
-- The body is baked views like the whistle's (art/metronome.py); the arm is not,
-- because it swings, so it is plotted here over the body every frame in the
-- projection the views were baked in, read off `Sprites.METRONOME.arm` and
-- `.cam` so the two cannot disagree about where the arm hangs.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Metronome = {}
Metronome.__index = Metronome

local TAU = math.pi * 2

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new): the
-- number on the row is the first cycle's.
local function scaled(e, damage) return damage * e.damage / e.def.damage end

function Metronome.new(def)
    local m = def.metronome
    return setmetatable({
        def = m,
        phase = 1,
        clock = 0,           -- beats since it walked on, fractional
        beat = 0,            -- the last whole beat it has acted on
        state = "idle",
        left = pick(m.cool, 1) * m.bar,   -- beats left of whatever it is doing
        move = nil,          -- the move it is counting in or playing
        last = nil, before = nil,
        rings = nil, sweep = nil, wall = nil,
        e = nil,
        orbit = love.math.random() < 0.5 and -1 or 1,  -- which way round you it roams
    }, Metronome)
end

function Metronome:busy()
    return self.state ~= "idle"
end

-- The arm's swing, in radians off upright: at an end of its swing on every
-- beat, one way on the even beats and the other on the odd.
function Metronome:swing()
    return self.def.swing * math.cos(math.pi * self.clock)
end

-- How long a beat is, in seconds, at the tempo it is playing at now.
function Metronome:beatLength()
    return 60 / pick(self.def.tempo, self.phase)
end

--- the clock ------------------------------------------------------------------

function Metronome:update(dt, game, e)
    self.e = e
    if dt <= 0 then return end

    -- The phase, at the eye's thirds: each one is a quicker tempo.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        Camera.knock(phase >= 3 and 3 or 2)
        game.particles:burst(e.x, e.y, phase >= 3 and 24 or 14, Palette.red)
        game:say("FASTER!")
    end

    -- Stuck to the page, it stops: the clock, the arm, and everything it is
    -- in the middle of with them. A count-in is dropped rather than held, so
    -- what it does when it comes free is start a fresh bar in front of you.
    if e.frozen > 0 then
        if self.state == "count" then
            self:clear()
            self.state, self.left = "rest", self.def.bar - (self.beat % self.def.bar)
        end
        -- The wall's notes are in the shots table, which keeps its own time;
        -- they are given back the time the clock is stopped so a held march
        -- does not run out of life half way across.
        if self.wall then
            for _, n in ipairs(self.wall.notes) do n.life = n.life + dt end
        end
        e.drive, e.hop = { hold = true }, 0
        return
    end

    self.clock = self.clock + dt / self:beatLength()
    while self.beat < math.floor(self.clock) do
        self.beat = self.beat + 1
        self:onBeat(game, e)
    end

    -- Between beats: the walk, the beam, the rings going off, the wall's slide.
    local into = self.clock - self.beat
    self:walk(game, e, into)
    if self.sweep then self:sweepUpdate(dt, game, e) end
    if self.rings then self:chordUpdate(dt, game, e) end
    if self.wall then self:scaleUpdate(dt, game, e) end
end

-- Where it is walking to: a point `keep` from you on the side it is already
-- on, turned a little further round each beat the way it is circling, so it
-- roams round you rather than marching at you. Inside the box, and never a
-- standing target -- it is recomputed every frame off where you are now.
function Metronome:roamTo(game, e)
    local p = game.player
    local dx, dy = e.x - p.x, e.y - p.y
    local a = (dx == 0 and dy == 0) and 0 or math.atan2(dy, dx)
    a = a + self.orbit * self.def.roam.turn
    local x = p.x + math.cos(a) * self.def.roam.keep
    local y = p.y + math.sin(a) * self.def.roam.keep
    if game.arena then x, y = game.arena:clamp(x, y, e.radius + 4) end
    return x, y
end

-- The walk: a hop for the first `step` of every beat and stood still for the
-- rest, whenever it is not planted for a move drawn round its own body. The hop
-- is drawing only (`hop`, read by Enemy:footing), like the eye's: the hitbox
-- stays on the floor.
function Metronome:walk(game, e, into)
    local planted = self.move == "sweep" or self.move == "chord"
    if self.state == "idle" then e.face = nil end
    if planted or into >= self.def.step then
        e.drive, e.hop = { hold = true }, 0
        return
    end
    local x, y = self:roamTo(game, e)
    e.drive = { seek = true, x = x, y = y }
    e.hop = math.floor(math.sin(math.pi * into / self.def.step) * self.def.roam.hop + 0.5)
end

-- One tick. The state machine moves only here, and only by whole bars, so every
-- move starts on a downbeat.
function Metronome:onBeat(game, e)
    local def = self.def
    local down = self.beat % def.bar == 0
    -- Heard on every beat, and higher on the one: the bar is something you can
    -- count along to with your eyes shut.
    Sfx.play("tick", down and 1.3 or 1.0)
    if down and self.beat % (self.def.roam.swap * self.def.bar) == 0 then
        self.orbit = -self.orbit
    end

    self.left = self.left - 1

    if self.state == "idle" then
        if self.beat % def.tick.every == 0 then self:throwNote(game, e) end
        if self.left <= 0 then self:choose(game, e) end
    elseif self.state == "count" then
        if self.move == "chord" then self:chordBeat(game, e, true) end
        if self.left <= 0 then
            self.state = "play"
            self.left = pick(def[self.move].bars, self.phase) * def.bar
            self.played = 0
            if self.move == "sweep" then self.sweep.hot = true; Camera.knock(1) end
            if self.move == "chord" then self:chordBeat(game, e, false) end
            if self.move == "scale" then self:scaleBeat(game, e) end
        end
    elseif self.state == "play" then
        self.played = self.played + 1
        if self.left <= 0 then
            self:clear()
            self.state, self.left = "rest", def.rest * def.bar
        else
            if self.move == "chord" then self:chordBeat(game, e, false) end
            if self.move == "scale" then self:scaleBeat(game, e) end
        end
    elseif self.state == "rest" then
        if self.left <= 0 then
            self.state, self.left = "idle", pick(def.cool, self.phase) * def.bar
        end
    end
end

-- Done with a move: whatever it put on the page comes off it.
function Metronome:clear()
    if self.wall then
        for _, s in ipairs(self.wall.notes) do s.life = 0 end
    end
    self.sweep, self.rings, self.wall, self.move = nil, nil, nil, nil
    if self.e then self.e.face = nil end
end

-- On every other beat while it walks: one note, straight at you.
function Metronome:throwNote(game, e)
    local t = self.def.tick
    local dx, dy = util.normalize(game.player.x - e.x, game.player.y - e.y)
    if dx == 0 and dy == 0 then return end
    game.shots[#game.shots + 1] = {
        x = e.x, y = e.y, dx = dx, dy = dy, speed = t.speed,
        damage = scaled(e, t.damage), life = t.life, sprite = t.sprite,
        radius = t.hit * e.reach, grow = e.grow,
    }
end

-- The choice, off how far away you are, and away from what it just did: the
-- sweep is for someone in front of it at middle distance, the chord for someone
-- close, the scale for someone keeping away -- and the scale is a whole-box
-- move, so it waits for the second phase.
function Metronome:choose(game, e)
    local def = self.def
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local w = {
        sweep = (d > 40 and d < def.sweep.length) and 1.4 or 0.5,
        chord = d < 110 and 1.5 or 0.6,
    }
    if self.phase >= def.scale.from then
        w.scale = d > 90 and 1.4 or 0.8
    end
    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.15 end
    if self.before and w[self.before] then w[self.before] = w[self.before] * 0.6 end

    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "sweep"
    for _, name in ipairs({ "sweep", "chord", "scale" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.before, self.last = self.last, move
    self.move, self.state, self.left = move, "count", def.bar
    self[move .. "Start"](self, game, e)
end

--- the sweep ------------------------------------------------------------------

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

-- The fan is locked facing you at the top of the count-in and the body turns to
-- it and stays turned, so the arm you see is the beam you get.
function Metronome:sweepStart(game, e)
    local a = math.atan2(game.player.y - e.y, game.player.x - e.x)
    -- Snapped to the view it will be drawn at, so the beam leaves the arm.
    local n = #Sprites.metronomeViews
    a = math.floor(a / TAU * n + 0.5) / n * TAU
    e.face = a
    self.sweep = { a = a, hot = false }
end

-- Where the beam is pointing now: the arm leaning to its right swings the beam
-- to the fan's right as you look along it, which is to the left of the heading
-- -- the same side the arm is drawn going (Metronome.armPoint).
function Metronome:beamAngle()
    return self.sweep.a - self.def.sweep.fan * math.cos(math.pi * self.clock)
end

function Metronome:sweepUpdate(dt, game, e)
    local s, sw = self.def.sweep, self.sweep
    local a = self:beamAngle()
    local ox, oy = e.x + math.cos(a) * 10, e.y + math.sin(a) * 6
    local len = reach(game, ox, oy, a, s.length)
    sw.x0, sw.y0 = ox, oy
    sw.x1, sw.y1 = ox + math.cos(a) * len, oy + math.sin(a) * len
    if not sw.hot then return end
    local p = game.player
    if util.distToSegment(p.x, p.y, sw.x0, sw.y0, sw.x1, sw.y1) < p.radius + s.width / 2 then
        if p:hurt(scaled(e, s.damage)) then
            game.particles:burst(p.x, p.y, 6, Palette.red)
        end
    end
    if love.math.random() < 0.4 then
        game.particles:burst(sw.x1, sw.y1, 1, love.math.random() < 0.5 and Palette.red or Palette.ink)
    end
end

--- the chord ------------------------------------------------------------------

function Metronome:chordStart(game, e)
    local c = self.def.chord
    self.rings = { x = e.x, y = e.y, n = pick(c.count, self.phase), next = 1, hot = {} }
end

-- On a beat: in the count-in only the last beat matters, which is when the first
-- ring starts blinking; in play, a ring is struck and the one after it starts
-- to blink.
function Metronome:chordBeat(game, e, counting)
    local r = self.rings
    if counting then
        if self.left == 1 then r.warn = 1 end
        return
    end
    if r.next <= r.n then
        r.hot[r.next] = self.def.chord.flash
        r.next = r.next + 1
        r.warn = r.next <= r.n and r.next or nil
        Camera.knock(1)
    end
end

function Metronome:chordUpdate(dt, game, e)
    local c, r = self.def.chord, self.rings
    local p = game.player
    local d = util.len(p.x - r.x, p.y - r.y)
    for k, t in pairs(r.hot) do
        if t > 0 then
            r.hot[k] = t - dt
            -- In it means your middle is on the band, give or take a couple of
            -- pixels: the room between two rings has to be room you can stand in.
            if math.abs(d - c.rings[k]) < c.width / 2 + 2 then
                if p:hurt(scaled(e, c.damage)) then
                    game.particles:burst(p.x, p.y, 6, Palette.red)
                end
            end
        end
    end
end

--- the scale ------------------------------------------------------------------

-- A wall of notes across the whole box, square on, starting at the edge on the
-- far side of the box from you so it has the whole box to cross before it
-- reaches you, with the hole wherever you are standing along it.
function Metronome:scaleStart(game, e)
    local sc = self.def.scale
    local p = game.player
    local box = game.arena or { left = e.x - 240, top = e.y - 135, w = 480, h = 270 }
    local cx, cy = box.left + box.w / 2, box.top + box.h / 2
    -- Across whichever way the box is longer from you, so the march is a march.
    local alongX = love.math.random() < 0.5
    local w = { notes = {}, alongX = alongX }
    local span, lat0, latSpan
    if alongX then
        w.dir = p.x >= cx and 1 or -1
        w.from = w.dir > 0 and box.left + 4 or box.left + box.w - 4
        span, lat0, latSpan = box.w - 8, box.top, box.h
    else
        w.dir = p.y >= cy and 1 or -1
        w.from = w.dir > 0 and box.top + 4 or box.top + box.h - 4
        span, lat0, latSpan = box.h - 8, box.left, box.w
    end
    w.step = span / sc.beats
    w.lat0, w.gap = lat0 + sc.gap / 2, sc.gap
    w.slots = math.max(4, math.floor(latSpan / sc.gap))
    w.holeW = sc.hole
    local you = ((alongX and p.y or p.x) - w.lat0) / w.gap
    w.hole = util.clamp(math.floor(you - (w.holeW - 1) / 2 + 0.5), 1, w.slots - w.holeW + 1)
    w.climb = love.math.random() < 0.5 and -1 or 1
    w.at, w.atFrom, w.slide = 0, 0, 0

    local life = (1 + pick(sc.bars, self.phase)) * self.def.bar * self:beatLength() + 1
    for slot = 1, w.slots do
        if slot < w.hole or slot >= w.hole + w.holeW then
            local s = {
                x = 0, y = 0, dx = 0, dy = 0, speed = 0,
                damage = scaled(e, sc.damage), life = life, sprite = sc.sprite,
                radius = sc.hit * e.reach, grow = e.grow, slot = slot,
            }
            w.notes[#w.notes + 1] = s
            game.shots[#game.shots + 1] = s
        end
    end
    self.wall = w
    self:scalePlace(0)
end

-- A step forward and a note up: the wall moves on by one step and the note at
-- the hole's leading edge jumps over it to the trailing edge, which is the hole
-- walking one note along. At the end of the run it turns round.
--
-- The jump is a jump, not a slide. A note sliding across the hole would sweep
-- through whoever was standing in it, which is the one place the move promises
-- is safe -- and with the hole three notes wide, the middle of the hole before
-- the climb is still clear of every note after it, so walking with the hole is
-- something you can do a beat late without being punished for it.
function Metronome:scaleBeat(game, e)
    local w = self.wall
    w.atFrom, w.at, w.slide = w.at, math.min(w.at + 1, self.def.scale.beats), self.def.scale.slide
    local nextHole = w.hole + w.climb
    if nextHole < 1 or nextHole + w.holeW - 1 > w.slots then
        w.climb = -w.climb
        nextHole = w.hole + w.climb
    end
    local entering = w.climb > 0 and w.hole + w.holeW or w.hole - 1
    local leaving = w.climb > 0 and w.hole or w.hole + w.holeW - 1
    for _, s in ipairs(w.notes) do
        if s.slot == entering then s.slot = leaving end
    end
    w.hole = nextHole
end

function Metronome:scalePlace(f)
    local w = self.wall
    local at = w.atFrom + (w.at - w.atFrom) * f
    local along = w.from + w.dir * at * w.step
    for _, s in ipairs(w.notes) do
        local lat = w.lat0 + (s.slot - 1) * w.gap
        if w.alongX then s.x, s.y = along, lat else s.x, s.y = lat, along end
    end
end

function Metronome:scaleUpdate(dt, game, e)
    local w = self.wall
    w.slide = math.max(0, w.slide - dt)
    self:scalePlace(1 - w.slide / self.def.scale.slide)
end

--- drawing --------------------------------------------------------------------

-- A point on the arm, `along` model units up it from its pivot with the arm
-- swung `swing` off upright, for the body drawn at view `view`: in pixels from
-- the body's origin, plus how near the viewer it is. The same sums
-- art/metronome.py's preview does, off the numbers it baked.
function Metronome.armPoint(view, swing, along)
    local M = Sprites.METRONOME
    local arm, cam = M.arm, M.cam
    local h = (view - 1) * TAU / #Sprites.metronomeViews
    local dx, dy, dz = arm.lean, math.cos(swing), math.sin(swing)
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    local mx = arm.x + dx / l * along
    local my = arm.y + dy / l * along
    local mz = arm.z + dz / l * along
    local a = h + math.pi
    local c, s = math.cos(a), math.sin(a)
    local x, z = mx * c - mz * s, mx * s + mz * c
    local cy = my * math.cos(cam.pitch) - z * math.sin(cam.pitch)
    return x / cam.unit + cam.bias, -cy / cam.unit + cam.bias
end

-- Whether the arm is on the near side of the body at this view, which is whether
-- the panel it hangs in front of is turned towards you at all.
function Metronome.armInFront(view)
    local h = (view - 1) * TAU / #Sprites.metronomeViews
    return math.sin(h) > -0.2
end

-- The pendulum: a rod of ink and a weight on it, at body `x, y` (where the
-- sprite is drawn). `colour` draws all of it flat in one colour, for the blank
-- under it and the hit flash; otherwise the weight blinks red through a
-- count-in, which is the tell that something is coming on the next downbeat.
function Metronome:drawArm(e, x, y, colour)
    local view = e.view or 1
    local M = Sprites.METRONOME
    local swing = self:swing()
    local bx, by = math.floor(x), math.floor(y)
    local x0, y0 = Metronome.armPoint(view, swing, 0)
    local x1, y1 = Metronome.armPoint(view, swing, M.arm.len)
    local wx, wy = Metronome.armPoint(view, swing, M.arm.len * M.arm.bob)
    love.graphics.setColor(colour or Palette.ink)
    pixelart.line(bx + x0, by + y0, bx + x1, by + y1)
    local cx, cy = bx + math.floor(wx) - 2, by + math.floor(wy) - 1
    love.graphics.rectangle("fill", cx, cy, 5, 4)
    if not colour then
        local warn = self.state == "count" and math.floor(self.clock * 4) % 2 == 0
        love.graphics.setColor(warn and Palette.red or Palette.graphite)
        love.graphics.rectangle("fill", cx + 1, cy + 1, 3, 2)
    end
end

-- Dashes along a line, marching outwards: the tells.
local function dashes(x, y, a, len, shift, on)
    on = on or 3
    local dx, dy = math.cos(a), math.sin(a)
    for d = 0, len, 1 do
        if math.floor((d - shift) / on) % 2 == 0 then
            love.graphics.rectangle("fill", math.floor(x + dx * d), math.floor(y + dy * d), 1, 1)
        end
    end
end

-- A filled ring from `r0` to `r1`, a row at a time so it tiles.
local function annulus(cx, cy, r0, r1)
    cx, cy = math.floor(cx), math.floor(cy)
    for dy = -r1, r1 do
        local outer = math.floor(math.sqrt(math.max(0, r1 * r1 - dy * dy)))
        local inner = math.abs(dy) < r0 and math.floor(math.sqrt(r0 * r0 - dy * dy)) or -1
        if inner < 0 then
            love.graphics.rectangle("fill", cx - outer, cy + dy, outer * 2 + 1, 1)
        else
            love.graphics.rectangle("fill", cx - outer, cy + dy, outer - inner, 1)
            love.graphics.rectangle("fill", cx + inner + 1, cy + dy, outer - inner, 1)
        end
    end
end

-- A ring's outline drawn dotted, so it reads as somewhere a thing *will* be.
local function dottedRing(cx, cy, r, phase)
    local n = math.max(12, math.floor(r * 0.9))
    for i = 0, n - 1 do
        if (i + phase) % 2 == 0 then
            local a = i / n * TAU
            love.graphics.rectangle("fill", math.floor(cx + math.cos(a) * r),
                math.floor(cy + math.sin(a) * r), 1, 1)
        end
    end
end

-- On the floor: the chord's rings and the sweep's fan, both places to keep off.
function Metronome:drawGround(time)
    local r = self.rings
    if r then
        local c = self.def.chord
        for k = 1, r.n do
            local rad = c.rings[k]
            local hot = r.hot[k]
            if hot and hot > 0 then
                love.graphics.setColor(Palette.red)
                annulus(r.x, r.y, rad - c.width / 2, rad + c.width / 2)
            elseif not hot then
                local warn = r.warn == k and math.floor(time * 8) % 2 == 0
                love.graphics.setColor(warn and Palette.red or Palette.slate)
                dottedRing(r.x, r.y, rad - c.width / 2, math.floor(time * 6))
                dottedRing(r.x, r.y, rad + c.width / 2, math.floor(time * 6))
            end
        end
    end

    local sw = self.sweep
    if sw and self.e then
        local s, e = self.def.sweep, self.e
        love.graphics.setColor(sw.hot and Palette.red or Palette.slate)
        for _, side in ipairs({ -1, 1 }) do
            local a = sw.a + side * s.fan
            dashes(e.x + math.cos(a) * 10, e.y + math.sin(a) * 6, a, s.length, time * 20)
        end
        local steps = math.floor(s.fan * 2 * s.length / 4)
        for i = 0, steps do
            local a = sw.a - s.fan + i / steps * s.fan * 2
            love.graphics.rectangle("fill", math.floor(e.x + math.cos(a) * s.length),
                math.floor(e.y + math.sin(a) * s.length), 1, 1)
        end
    end
end

-- Over the crowd: the sweep's beam, or its ghost swinging through the count-in.
function Metronome:drawAir(time, e)
    local sw = self.sweep
    if not (sw and sw.x1) then return end
    if sw.hot then
        love.graphics.setColor(Palette.red)
        pixelart.band(sw.x0, sw.y0, sw.x1, sw.y1, self.def.sweep.width)
        pixelart.circleFill(sw.x1, sw.y1, 2)
        love.graphics.setColor(Palette.paper)
        pixelart.band(sw.x0, sw.y0, sw.x1, sw.y1, 1)
    else
        love.graphics.setColor(math.floor(time * 10) % 2 == 0 and Palette.red or Palette.slate)
        dashes(sw.x0, sw.y0, math.atan2(sw.y1 - sw.y0, sw.x1 - sw.x0),
            util.len(sw.x1 - sw.x0, sw.y1 - sw.y0), time * 40)
    end
end

return Metronome
