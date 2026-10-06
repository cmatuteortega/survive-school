-- The GRAMMAR boss's mind: a fat dictionary, and the fight in the book about
-- *lines*.
--
-- The eye is a fight about the ground, the whistle the air, the metronome time,
-- the die number and the stamp cells. This one is about the page GRAMMAR is
-- written on: ruling that comes in pairs, two lines ten apart and then a gap
-- twice as deep (`GROUPED` in src/subjects.lua). A pair of lines is where words
-- go, the gap is where they do not, and everything the dictionary does is
-- measured off that -- its pages are a whole number of groups tall with their
-- head and tail on printed rules, and what it writes, it writes on the lines.
-- The drills on this page are the pincer above all, two of something either
-- side of you, and so is the move it is named for: a book shuts from both sides.
--
-- **It moves like a book that bites.** It lies on the page and comes at you in
-- hops, mouth first -- the front board lifted off the pages before it goes and
-- snapped shut as it lands -- which are its body's poses (`poses` on its row in
-- src/solids.lua): shut, ajar and open, the board swinging between them. The
-- brain says which through `e.pose` and how high off the page through `e.hop`,
-- and while a clap shuts it stands the open leaves up off the page to meet
-- (`fold`). The board up is the tell for everything it does, short for a hop and
-- long for the moves.
--
--  - **It hops at you**, and every couple of seconds tears out a page and flicks
--    it at you, so standing still is never free.
--  - **The clap.** Mouth open at you, while two pages are outlined on the paper
--    either side of a spine, following you for as long as it is open -- then it
--    leaps onto the spine and lands open on its back. A moment later it shuts:
--    the fore-edges of both pages sweep in to the spine, and whoever is between
--    them is caught. The answer is never *which side*, because both sides are
--    coming: it is out of the head or the tail, which are on the ruling, or out
--    past an edge before it starts. Shut, it is stuck where it is for a second:
--    the window the move paid for.
--  - **The riffle.** Lying open, it turns its pages at you: a fan of leaves a
--    page, every other one shifted half a gap across, so the gap you stood in is
--    where the next leaf is -- one way, then back.
--  - **The definition.** From the second third: it writes, on every pair of lines
--    round you, left to right the way a page is read, a line starting when the
--    one above is a way along. Ink on the lines is wet and hurts; the gaps are
--    where you stand. At the last third it writes again once the lines have dried
--    -- *between* the lines -- so the gap you hid in is the one place you cannot
--    stay, and the line is the one place you can.
--
-- **Glue holds it to the page.** A glued dictionary drops whatever it was doing
-- where it is, shut -- out of the air if it was in the air, a clap let go without
-- shutting on anyone -- and lies there for the rest of the hold.

local Palette = require("src.palette")
local Solids = require("src.solids")
local Camera = require("src.camera")
local Font = require("src.font")
local I18n = require("src.i18n")
local Sfx = require("src.sfx")
local util = require("src.util")

local Dictionary = {}
Dictionary.__index = Dictionary

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new): the
-- number on the row is the first cycle's.
local function scaled(e, damage) return damage * e.damage / e.def.damage end

--- the ruling -----------------------------------------------------------------

-- The page's numbers (`GROUPED` in src/subjects.lua), which this file has to
-- agree with to the pixel for a page to stop on a rule. A group is thirty deep:
-- a rule two thick at the top, another ten below it, then the gap. The *line*
-- is the pair and what is between them, the first twelve; the gap is the rest.
local GROUP, LINE = 30, 12

-- Every word it writes, cycled along each line it writes on.
local WORDS = { "NOUN", "VERB", "ADJECTIVE", "ADVERB", "PRONOUN" }

--- the brain ------------------------------------------------------------------

function Dictionary.new(def)
    local d = def.dictionary
    return setmetatable({
        def = d,
        phase = 1,
        state = "idle",
        t = pick(d.cool, 1),
        hopT = pick(d.hop.every, 1) * 0.5,
        leafT = d.leaf.every * 0.6,
        jump = nil,         -- the leap it is in the air for, if it is
        book = nil,         -- the two pages of a clap, on the paper
        writing = {},       -- lines it has written, wet and dry
        pass = nil,         -- the lines it is writing now, or is about to
        last = nil, before = nil,
        e = nil,
    }, Dictionary)
end

function Dictionary:busy()
    return self.state ~= "idle"
end

function Dictionary:pose(e, name, hop)
    e.pose, e.hop = name, hop or 0
end

-- Where on the page the floor under the book is: the spine, for the clap.
local function foot() return Solids.dictionary.foot end

function Dictionary:update(dt, game, e)
    self.e = e
    if dt <= 0 then return end

    -- Ink dries whatever the book is doing, glued or not: it is on the page.
    self:inkUpdate(dt, game)

    -- The phase, at the eye's thirds. The second unlocks the definition and
    -- says so.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        Camera.knock(phase >= 3 and 3 or 2)
        game.particles:burst(e.x, e.y, phase >= 3 and 24 or 14, Palette.red)
        game:say(phase == 2 and "DEFINITION!" or "FASTER!")
    end

    -- Stuck to the page: down, shut and still. A move it was in the middle of
    -- is dropped rather than finished, and what it does when it comes free is
    -- start again. Writing already on the page stays there and dries.
    if e.frozen > 0 then
        if self.state ~= "idle" and self.state ~= "rest" then
            self.jump, self.book = nil, nil
            if self.pass then self:dry(self.pass) end
            self.pass = nil
            self.state, self.t = "rest", 0.4
        end
        self:pose(e, "shut", 0)
        e.drive = { hold = true }
        e.face = nil
        return
    end

    self.t = self.t - dt
    e.drive = { hold = true }
    -- What hurts in a move is the pages and the ink, never the body brushing you
    -- on its way between the two: the clap's spine is put a page away from you,
    -- and lying open in the middle of its own pages it is close enough to touch.
    if self.state ~= "idle" and self.state ~= "rest" then
        e.hitCooldown = math.max(e.hitCooldown, 0.1)
    end
    if self.jump then self:fly(dt, game, e) end
    self[self.state](self, dt, game, e)
end

--- leaping --------------------------------------------------------------------

-- A leap from where it lies to (x, y) over `time`, `high` pixels at the top,
-- calling `land` when it comes down: the stamp's leap (src/stamp.lua), and never
-- quicker than LEAP_MOST a second for the same reason -- a book that crossed the
-- box in a tenth of a second would not be seen to move.
local LEAP_MOST = 500

function Dictionary:leap(e, x, y, time, high, land, air)
    time = math.max(time, util.len(x - e.x, y - e.y) / LEAP_MOST)
    self.jump = { x0 = e.x, y0 = e.y, x1 = x, y1 = y, time = time, t = 0,
                  high = high, land = land, air = air }
end

function Dictionary:fly(dt, game, e)
    local j = self.jump
    j.t = j.t + dt
    local f = math.min(1, j.t / j.time)
    e.x = j.x0 + (j.x1 - j.x0) * f
    e.y = j.y0 + (j.y1 - j.y0) * f
    e.headX, e.headY = util.normalize(j.x1 - j.x0, j.y1 - j.y0)
    local h = math.floor(4 * j.high * f * (1 - f) + 0.5)
    -- Mouth open on the way up, and whatever the move wants on the way down: a
    -- hop bites shut, a clap comes down already open.
    self:pose(e, f < 0.5 and "ajar" or (j.air or "shut"), h)
    -- Over your head is not touching you.
    if h > 6 then e.hitCooldown = math.max(e.hitCooldown, 0.1) end
    if f >= 1 then
        self.jump = nil
        self:pose(e, j.air or "shut", 0)
        if j.land then j.land(self, game, e) end
    end
end

-- A page torn out and flicked at `a`.
function Dictionary:flick(game, e, a, leaf)
    leaf = leaf or self.def.leaf
    game.shots[#game.shots + 1] = {
        x = e.x, y = e.y + foot() - 4, dx = math.cos(a), dy = math.sin(a),
        speed = leaf.speed, damage = scaled(e, leaf.damage), life = leaf.life,
        sprite = "leaf", radius = leaf.hit * e.reach, grow = e.grow,
    }
end

--- walking about --------------------------------------------------------------

function Dictionary:idle(dt, game, e)
    local def = self.def
    e.face = nil
    if not self.jump then
        self.hopT = self.hopT - dt
        if self.hopT <= 0 then
            -- A hop at you: a short leap a little way along the line to you.
            self.hopT = pick(def.hop.every, self.phase)
            local p = game.player
            local dx, dy, d = util.normalize(p.x - e.x, p.y - e.y)
            local step = math.min(def.hop.reach, math.max(0, d - 12))
            local x, y = e.x + dx * step, e.y + dy * step
            if game.arena then x, y = game.arena:clamp(x, y, e.radius + 2) end
            self:leap(e, x, y, def.hop.time, def.hop.high, function(s, g, en)
                g.particles:burst(en.x, en.y + foot(), 3, Palette.slate)
            end)
        else
            self:pose(e, self.hopT < def.hop.rear and "ajar" or "shut", 0)
        end
    end

    self.leafT = self.leafT - dt
    if self.leafT <= 0 then
        self.leafT = def.leaf.every
        self:flick(game, e, math.atan2(game.player.y - e.y, game.player.x - e.x))
    end

    if self.t <= 0 and not self.jump then self:choose(game, e) end
end

-- The choice, off how far away you are and away from what it just did: the
-- clap for someone near, the riffle for someone keeping their distance, the
-- definition -- a whole-page move -- once the second third has unlocked it.
function Dictionary:choose(game, e)
    local def = self.def
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local w = {
        clap = d < 150 and 1.5 or 0.9,
        riffle = d > 60 and 1.2 or 0.6,
    }
    if self.phase >= def.definition.from then w.definition = 1.0 end
    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.15 end
    if self.before and w[self.before] then w[self.before] = w[self.before] * 0.6 end

    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "clap"
    for _, name in ipairs({ "clap", "riffle", "definition" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.before, self.last = self.last, move
    self[move .. "Start"](self, game, e)
end

-- Done with a move: lying where it stopped for the window the move paid for.
function Dictionary:rest(dt, game, e)
    self:pose(e, "shut", 0)
    if self.t <= 0 then
        self.state, self.t = "idle", pick(self.def.cool, self.phase)
        self.book = nil
        e.face = nil
    end
end

function Dictionary:restFor(t)
    self.state, self.t = "rest", t
    self.book = nil
end

--- the clap -------------------------------------------------------------------

-- The two pages it will lie open across, round you: a spine `reach` short of
-- halfway to you -- between you and where the book is, so it is the far page
-- you are standing on -- and a span a whole number of groups deep with its head
-- and tail on printed rules, round where you are standing.
function Dictionary:spread(game, e)
    local c = self.def.clap
    local p = game.player
    local reach, lines = pick(c.reach, self.phase), pick(c.lines, self.phase)
    local side = p.x >= e.x and 1 or -1
    local sx = p.x - side * reach * 0.5
    local top = math.floor(p.y / GROUP - lines / 2 + 0.5) * GROUP
    local box = game.arena
    if box then
        -- The spine has to be somewhere the body can lie, which is inside the
        -- box. Moved along a line, or by whole groups up or down the page, so
        -- the head and tail stay on the ruling.
        local pad = e.radius + 2
        sx = util.clamp(sx, box.left + pad, box:right() - pad)
        for _ = 1, 4 do
            local sy = top + lines * GROUP / 2 - foot()
            if sy < box.top + pad then top = top + GROUP
            elseif sy > box:bottom() - pad then top = top - GROUP
            else break end
        end
    end
    return { x = sx, top = top, bottom = top + lines * GROUP, reach = reach,
             edge = reach, open = false }
end

function Dictionary:clapStart(game, e)
    self.state, self.t = "clap", pick(self.def.clap.rear, self.phase)
    self.book = self:spread(game, e)
end

function Dictionary:clap(dt, game, e)
    local c = self.def.clap
    local b = self.book
    if self.jump then return end
    if not b.open then
        if self.t > 0 then
            -- Mouth open at you, the pages following you until the moment it goes.
            self:pose(e, "ajar", 0)
            self.book = self:spread(game, e)
            return
        end
        -- Locked. Square to the page in the air, so it lands with its pages
        -- along the ruling and the spine across it.
        e.face = 0
        local x, y = b.x, (b.top + b.bottom) / 2 - foot()
        self:leap(e, x, y, c.fly, c.high, function(d, g, en)
            b.open, d.t = true, pick(c.hold, d.phase)
            g.particles:burst(en.x, en.y + foot(), 6, Palette.slate)
            Camera.knock(1)
        end, "open")
        return
    end
    self:pose(e, "open", 0)
    if self.t > 0 then return end

    -- Shutting: both fore-edges in to the spine over `close`. Whoever an edge
    -- passes over on its way in is caught, once.
    local was = b.edge
    b.edge = math.max(0, b.edge - b.reach / c.close * dt)
    -- And the book shuts with them: both leaves stand up off the page as the
    -- edges come in, and meet over the spine as they get there.
    if e.solid then e.solid:set("fold", 1 - b.edge / b.reach) end
    local p = game.player
    local off = math.abs(p.x - b.x)
    if not b.hit and p.y >= b.top - 1 and p.y <= b.bottom + 1
        and off <= was + 2 and off >= b.edge - 2 then
        b.hit = true
        if p:hurt(scaled(e, c.damage)) then
            game.particles:burst(p.x, p.y, 8, Palette.red)
        end
    end
    if b.edge <= 0 then
        self:pose(e, "shut", 0)
        e.face = nil
        Camera.knock(c.knock)
        Sfx.play("stamp")
        game.particles:burst(e.x, e.y + foot(), 10, Palette.red)
        -- From the second third the pages it shut on blow out of it.
        local n = pick(c.splash, self.phase)
        for k = 1, n do self:flick(game, e, (k - 0.5) / n * math.pi * 2) end
        self:restFor(pick(c.rest, self.phase))
    end
end

--- the riffle -----------------------------------------------------------------

-- Pages turned at you, a fan of leaves a turn. The fan is aimed once, where you
-- were when it opened, and every other turn it is shifted half a gap across, so
-- where the leaves were is where the gaps are next: you step one way and back,
-- in time with the pages. `spread` is wide enough that the gap between two
-- leaves is a gap a body fits through at any distance it is fired from.
function Dictionary:riffleStart(game, e)
    self.state, self.t = "riffle", self.def.riffle.rear
    self.fan = nil
end

function Dictionary:riffle(dt, game, e)
    local r = self.def.riffle
    if not self.fan then
        self:pose(e, "ajar", 0)
        if self.t > 0 then return end
        self.fan = { a = math.atan2(game.player.y - e.y, game.player.x - e.x),
                     left = pick(r.turns, self.phase), gap = 0, k = 0 }
        e.face = self.fan.a
    end
    local f = self.fan
    self:pose(e, "open", 0)
    f.gap = f.gap - dt
    if f.gap <= 0 and f.left > 0 then
        f.gap, f.left, f.k = pick(r.every, self.phase), f.left - 1, f.k + 1
        local n = pick(r.leaves, self.phase)
        local shift = (f.k % 2 == 0) and r.spread / 2 or 0
        for i = 1, n do
            self:flick(game, e, f.a + shift + (i - (n + 1) / 2) * r.spread)
        end
    end
    if f.left <= 0 and f.gap <= 0 then
        self.fan = nil
        e.face = nil
        self:restFor(r.rest)
    end
end

--- the definition -------------------------------------------------------------

-- One pass of writing: the lines -- or the gaps, `between` -- of every group
-- within `rows` of yours that is in the box, each with the words it will
-- write, the first starting at once and each after it `lag` later.
function Dictionary:passOver(game, between)
    local d = self.def.definition
    local p = game.player
    local box = game.arena
    local rows = pick(d.rows, self.phase)
    local g0 = math.floor(p.y / GROUP)
    local x0 = box and box.left + 3 or p.x - 200
    local x1 = box and box:right() - 3 or p.x + 200
    local words = {}
    for k, w in ipairs(WORDS) do words[k] = I18n.t(w) end
    local lines = {}
    for g = g0 - rows, g0 + rows do
        local ya = g * GROUP + (between and LINE or 0)
        local yb = g * GROUP + (between and GROUP or LINE)
        if not box or (yb > box.top and ya < box:bottom()) then
            -- The letters, split up front so drawing is a walk along a list.
            -- Gaps are deep enough for two rows of writing, which is what makes
            -- a gap written in read as full rather than as underlined.
            local rowsOf = between and { ya + 3, ya + 10 } or { ya + 3 }
            local text = {}
            for r, ty in ipairs(rowsOf) do
                local letters, n, i = {}, math.floor((x1 - x0) / Font.advance), g + r
                while #letters < n do
                    local w = words[i % #words + 1]
                    for k = 1, Font.count(w) do
                        if #letters >= n then break end
                        letters[#letters + 1] = Font.at(w, k)
                    end
                    if #letters < n then letters[#letters + 1] = " " end
                    i = i + 1
                end
                text[#text + 1] = { y = ty, letters = letters }
            end
            lines[#lines + 1] = { ya = ya, yb = yb, x0 = x0, x1 = x1, text = text,
                                  ruled = not between, delay = #lines * d.lag,
                                  cursor = x0, wet = math.huge, age = 0 }
        end
    end
    return lines
end

function Dictionary:definitionStart(game, e)
    local d = self.def.definition
    self.passes = pick(d.passes, self.phase)
    self.between = false
    self.pass = self:passOver(game, false)
    self.writeT = nil
    self.state, self.t = "definition", d.rear
end

function Dictionary:definition(dt, game, e)
    local d = self.def.definition
    self:pose(e, self.t > 0 and "ajar" or "open", 0)
    if self.t > 0 then return end
    self.writeT = (self.writeT or 0) + dt
    local done = true
    for _, l in ipairs(self.pass) do
        l.cursor = math.min(l.x1, l.x0 + math.max(0, self.writeT - l.delay) * d.speed)
        if l.cursor < l.x1 then done = false end
    end
    if not done then return end
    -- Written: the whole pass stays wet for `wet` and dries at once -- read as
    -- one page -- and it is filed with the rest of the ink.
    for _, l in ipairs(self.pass) do
        l.wet = d.wet
        self.writing[#self.writing + 1] = l
    end
    self.pass = nil
    self.passes = self.passes - 1
    if self.passes > 0 then
        -- Between the lines, counted in again. The lines' ink is left wet until
        -- the count-in is half done, so the line you have to step onto is wet
        -- when the gaps are outlined and dry before they are written.
        for _, l in ipairs(self.writing) do
            if l.wet > 0 then l.wet = math.min(l.wet, d.again * 0.5) end
        end
        self.between = not self.between
        self.pass = self:passOver(game, self.between)
        self.writeT = nil
        self.t = d.again
        return
    end
    self:restFor(d.rest)
end

-- Pulled off the page half written (glue): what is down stays and dries.
function Dictionary:dry(lines)
    for _, l in ipairs(lines) do
        if l.cursor > l.x0 then
            l.wet = 0
            self.writing[#self.writing + 1] = l
        end
    end
end

-- Whether a point is on written ink: in a line's depth, behind its pen.
local function onInk(l, x, y)
    return y >= l.ya and y < l.yb and x >= l.x0 and x <= l.cursor
end

function Dictionary:inkUpdate(dt, game)
    local p = game.player
    local dry = self.def.definition.dry
    local hurt = false
    local damage = self.e and scaled(self.e, self.def.definition.damage) or self.def.definition.damage
    -- The pen as it goes is wet too: the pass being written hurts from the first
    -- letter, not from when it is finished.
    if self.pass and not hurt then
        for _, l in ipairs(self.pass) do
            if l.cursor > l.x0 and onInk(l, p.x, p.y) then hurt = true break end
        end
    end
    for i = #self.writing, 1, -1 do
        local l = self.writing[i]
        l.wet = l.wet - dt
        if l.wet <= 0 then l.age = l.age + dt end
        if l.age > dry then
            table.remove(self.writing, i)
        elseif l.wet > 0 and not hurt and onInk(l, p.x, p.y) then
            hurt = true
        end
    end
    if hurt and p:hurt(damage) then game.particles:burst(p.x, p.y, 5, Palette.red) end
end

--- drawing --------------------------------------------------------------------

-- A row of dashes `len` long, for an outline about to be something.
local function dashes(x, y, len, shift)
    for i = 0, len - 1, 4 do
        if math.floor((i + shift) / 4) % 2 == 0 then
            love.graphics.rectangle("fill", math.floor(x + i), y, math.min(2, len - i), 1)
        end
    end
end
local function dashesDown(x, y, len, shift)
    for i = 0, len - 1, 4 do
        if math.floor((i + shift) / 4) % 2 == 0 then
            love.graphics.rectangle("fill", x, math.floor(y + i), 1, math.min(2, len - i))
        end
    end
end

-- A written line up to its pen: the words, and on a line the two rules gone
-- over in the same ink, so that what hurts is the whole depth of it.
local function written(l, colour)
    love.graphics.setColor(colour)
    local len = math.floor(l.cursor - l.x0)
    if len <= 0 then return end
    if l.ruled then
        love.graphics.rectangle("fill", l.x0, l.ya, len, 2)
        love.graphics.rectangle("fill", l.x0, l.ya + 10, len, 2)
    end
    local upto = math.floor(len / Font.advance)
    for _, row in ipairs(l.text) do
        for i = 1, math.min(upto, #row.letters) do
            local ch = row.letters[i]
            if ch ~= " " then Font.print(ch, l.x0 + (i - 1) * Font.advance, row.y) end
        end
    end
end

-- On the floor: the writing, the lines about to be written on, and the pages a
-- clap is about to shut.
function Dictionary:drawGround(time)
    local dry = self.def.definition.dry
    for _, l in ipairs(self.writing) do
        if l.wet > 0 then
            written(l, Palette.red)
        else
            -- Dry: slate, then graphite, then blinking out -- down the ramp,
            -- not through alpha.
            local left = dry - l.age
            if left > dry * 0.5 then
                written(l, Palette.slate)
            elseif left > 1 or math.floor(left * 10) % 2 == 0 then
                written(l, Palette.graphite)
            end
        end
    end

    local blink = math.floor(time * 8) % 2 == 0
    local shift = math.floor(time * 20)
    if self.pass then
        for _, l in ipairs(self.pass) do
            if l.cursor > l.x0 then written(l, Palette.red) end
            -- Still to come: its depth outlined, and the pen blinking at the
            -- start of it.
            if l.cursor < l.x1 then
                local from = math.floor(l.cursor)
                love.graphics.setColor(Palette.slate)
                dashes(from, l.ya, l.x1 - from, shift)
                dashes(from, l.yb - 1, l.x1 - from, shift)
                if blink or l.cursor > l.x0 then
                    love.graphics.setColor(Palette.red)
                    love.graphics.rectangle("fill", from, l.ya, 1, l.yb - l.ya)
                end
            end
        end
    end

    local b = self.book
    if b then
        local w, h = b.reach, b.bottom - b.top
        local x = math.floor(b.x)
        if not b.open then
            -- Coming: the two pages in dashes, the spine down the middle.
            love.graphics.setColor(blink and Palette.red or Palette.slate)
            dashes(x - w, b.top, w * 2, shift)
            dashes(x - w, b.bottom - 1, w * 2, shift)
            dashesDown(x - w, b.top, h, shift)
            dashesDown(x + w, b.top, h, shift)
            love.graphics.setColor(Palette.slate)
            dashesDown(x, b.top, h, shift)
        else
            -- Lying open: what is left of the two pages, solid, their
            -- fore-edges doubled -- the thing coming in -- and a print of lines
            -- across them so they read as pages.
            local e = math.floor(b.edge)
            love.graphics.setColor(Palette.red)
            love.graphics.rectangle("fill", x - e, b.top, e * 2 + 1, 1)
            love.graphics.rectangle("fill", x - e, b.bottom - 1, e * 2 + 1, 1)
            love.graphics.rectangle("fill", x - e, b.top, 2, h)
            love.graphics.rectangle("fill", x + e - 1, b.top, 2, h)
            love.graphics.setColor(blink and Palette.red or Palette.slate)
            for y = b.top + 4, b.bottom - 4, 5 do
                for i = 4, e - 3, 3 do
                    love.graphics.rectangle("fill", x - i, y, 1, 1)
                    love.graphics.rectangle("fill", x + i, y, 1, 1)
                end
            end
        end
    end
end

function Dictionary:drawAir() end

Dictionary.GROUP, Dictionary.LINE = GROUP, LINE

return Dictionary
