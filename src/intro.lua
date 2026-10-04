-- The opening: first day back, seen through the player's own eyes.
--
-- Everything here is looked at through one hole in the dark, a circle cut out
-- of a screen of ink, and the circle is an eye. It opens slowly on the first
-- scene the way an eye opens first thing in the morning, blinks between scenes,
-- and shuts for good before the last one. Then it opens one last time and does
-- not stop opening: it widens past the edges of the screen, and what was behind
-- it the whole time is the title page. The book opens where the player nods off.
--
-- The story is eight scenes and a row each in `Intro.scenes`, read top to bottom:
-- the blackboard says where you are, the clock says it is one minute into the
-- lesson, someone whispers to ask when it ends and someone whispers back, the
-- clock says two minutes have gone, and the board says something about maths
-- that nobody heard. Each scene waits for a tap. A tap while something is still
-- being written finishes it, and the next tap blinks. That is the rule a
-- dialogue box follows everywhere, and it means nobody has to watch the lettering
-- go down a second time.
--
-- It plays once per book (`Intro.seen`, saved with the options). It is a joke
-- told once, and a joke told on every launch stops being one. So there is a
-- SKIP in the top corner for anyone who has seen it, and it has to be *held*
-- for a moment: one stray tap on it would throw away the whole opening, and a
-- tap anywhere else is already the way forward.
--
-- The eye is drawn as lids rather than a mask. Every row of the canvas outside
-- an ellipse is filled with ink, a span each side, so nothing ever covers the
-- scene in a translucent dark. The lids are ink, the darkest thing in the
-- palette, and a blink is the ellipse squashing. It loses most of its height
-- and a quarter of its width, closes to a slit and comes back. It never quite
-- closes, because a real blink is over before you see the dark. The scene is
-- swapped at the slit.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Font = require("src.font")
local Background = require("src.background")
local Overprint = require("src.overprint")
local Subjects = require("src.subjects")
local Particles = require("src.particles")
local Scribble = require("src.scribble")
local Hud = require("src.hud")
local Input = require("src.input")
local I18n = require("src.i18n")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Intro = {}

-- Whether this book has been opened before. Owned here and written by
-- src/options.lua, the way every other setting is. A file with no line for it
-- is a book that has not seen the opening, an update included, so it plays once
-- for everyone.
Intro.seen = false

-- The script. `board` is chalk on the blackboard, a line per entry, each wrapped
-- to the board. `clock` is the wall clock, `at` seconds past midnight, and it
-- ticks forward from there until the minute hand moves. `notebook` is the
-- first lesson's page with the doodles on it, and the whispering is written
-- straight onto it, passed back and forth the way a note is: `write` is what goes
-- down, in `color`, and `rub` is what was there from the scene before and is
-- rubbed out first. `doodle` is the scene the doodles get drawn in (they stay on
-- the page after that). `dark` is the eyes shut, and `say` is typed into the
-- dark.
--
-- The question is in blue and the answer in red, and those are the two sides of
-- every page in this game (src/palette.lua): blue is you and red is everybody
-- else.
--
-- Every word in here is English and goes through `I18n.t` at the draw. MS
-- TEACHER is a name, and it stays a name in every language. Nobody heard what
-- the last lesson was about, so it is SOMETHING, SOMETHING MATHS whatever the
-- timetable's first page is.
Intro.scenes = {
    { kind = "board", lines = { "BACK TO SCHOOL" } },
    { kind = "board", lines = { "MS TEACHER", "FIRST LESSON" } },
    { kind = "clock", at = 9 * 3600 + 57 },
    { kind = "notebook", write = "... PST ... WHEN DOES THE CLASS END?", color = "blue", doodle = true },
    { kind = "notebook", rub = "... PST ... WHEN DOES THE CLASS END?", rubColor = "blue",
        write = "AT 10", color = "red" },
    { kind = "clock", at = 9 * 3600 + 2 * 60 + 57 },
    { kind = "board", lines = { "SOMETHING, SOMETHING MATHS" } },
    { kind = "dark", say = "..." },
}

--- timing --------------------------------------------------------------------

-- The open eye, as a share of the short edge of the canvas: a circle wholly on
-- screen with dark round it, so it reads as a hole from the first frame rather
-- than as a vignette.
local EYE = 0.47

-- A blink. Fast down, the shortest of holds at the bottom, and a slower lift,
-- which is the shape a real one has.
local BLINK_DOWN, BLINK_HOLD, BLINK_UP = 0.11, 0.06, 0.2
local SQUASH_X = 0.25  -- the share of its width the eye loses at the bottom
local SLIT = 2         -- pixels of scene left showing at the bottom

-- The first opening. A beat of dark long enough to read as eyes shut and not
-- as a frame that has not loaded yet, then the slow lift of someone waking.
local WAKE_DARK, WAKE_OPEN = 0.6, 1.0

-- Shutting for good before the last scene: the lids close all the way and stay.
local SHUT = 0.35

-- The last opening: up to the eye's own size, a held beat at that size so it
-- reads as the same eye, then wide until the circle is off every corner.
local REVEAL_OPEN, REVEAL_HOLD, REVEAL_WIDE = 0.8, 0.15, 0.55

local SKIP_HOLD = 1.2  -- seconds SKIP has to be held

-- The write-on, after a beat of the scene being looked at. Chalk is a touch
-- slower than the title's pencil (src/menu.lua), and every stop and comma is a
-- pause. That pause is what makes "... PST ..." sound like whispering.
local LEAD = 0.35
local WRITE_STEP = 0.07
local PEN_STEP = 0.055  -- pencil on the page, quicker than chalk
local PAUSE_STEP = 0.2
local DOT_STEP = 0.45  -- the last scene's three dots, typed into the dark

local DOODLE_TIME = 0.55 -- each of the three doodles, drawn one after another

-- Rubbing the question out: an eraser going back and forth across it, a swish
-- of the brush per pass, while the letters drop out a stamp at a time -- the
-- dither every fade here is made of -- and crumbs come off the rub. Then a beat
-- of clean page before the answer goes down where the question was.
local RUB_TIME, RUB_PASSES, RUB_GAP = 0.9, 3, 0.2
local DOODLE_SCALE = 2   -- close up, so twice the size they walk the page at

local TICKS = 3          -- ticks before the minute turns: `at` is :57
local TICK_LEAD = 0.25

local TITLE_SCALE = 3    -- the title's own size (src/menu.lua), for the chalk

--- easing --------------------------------------------------------------------

local function easeOut(f)
    f = util.clamp(f, 0, 1)
    return 1 - (1 - f) * (1 - f)
end

local function easeIn(f)
    f = util.clamp(f, 0, 1)
    return f * f
end

--- lettering -----------------------------------------------------------------

-- When each letter goes down, as one list across every line, from `start`.
-- Punctuation holds the pen for longer than a letter does. Returns the list
-- and the moment the last letter's beat is over.
local function typeTimes(lines, start, step)
    local times, t = {}, start
    for _, line in ipairs(lines) do
        for i = 1, Font.count(line) do
            times[#times + 1] = t
            local ch = Font.at(line, i)
            local pause = ch == "." or ch == "," or ch == "?"
            t = t + (pause and math.max(step, PAUSE_STEP) or step)
        end
    end
    return times, t
end

local function countBy(times, t)
    local n = 0
    for _, at in ipairs(times) do
        if at <= t then n = n + 1 end
    end
    return n
end

-- Lines wrapped to `width` canvas pixels at the largest of `scales` they fit at
-- in at most `maxLines` lines. A word too long for even the smallest scale is
-- left long, which is the rule Font.wrap already keeps.
local function fitLines(texts, width, scales, maxLines)
    local lines, scale
    for _, s in ipairs(scales) do
        lines, scale = {}, s
        local fits = true
        for _, text in ipairs(texts) do
            for _, line in ipairs(Font.wrap(I18n.t(text), math.floor(width / s))) do
                lines[#lines + 1] = line
                if Font.width(line) * s > width then fits = false end
            end
        end
        if fits and #lines <= maxLines then break end
    end
    return lines, scale
end

--- setup ---------------------------------------------------------------------

function Intro:enter()
    self.index = 1
    self.clock = 0
    -- The first scene's clock starts behind zero by the length of the wake,
    -- so its lettering starts half way up the slow first opening and not on the
    -- first frame of dark.
    self.t = -(WAKE_DARK + WAKE_OPEN * 0.5)
    self.wakeT = 0
    self.blinkT = nil
    self.swapped = false
    self.doneAt = 0
    self.written = 0
    self.passes = 0
    self.particles = Particles.new()
    self.seed = love.math.random() * 997

    self.hold = 0
    self.holding = false
    -- A press already down when the opening starts is not a tap on it.
    self.wasDown = Input.pointerDown
    self.leaving = false

    Input.stickEnabled = false
end

function Intro:scene()
    return Intro.scenes[self.index]
end

--- layout --------------------------------------------------------------------

-- The eye's middle and its open radius. It sits in the middle of the whole
-- canvas, not the safe area: it is a picture of the room and not something to
-- press, and an eye off-centre on a phone with a notch would look like a fault.
function Intro:eye(game)
    local cx, cy = math.floor(game.vw / 2), math.floor(game.vh / 2)
    return cx, cy, math.max(24, math.floor(math.min(game.vw, game.vh) * EYE))
end

-- The board fills the eye side to side with its corners just past the edge of
-- it, which is what a board looks like from a desk near the front.
function Intro:board(game)
    local cx, cy, r = self:eye(game)
    local w, h = math.floor(r * 1.8), math.floor(r * 1.12)
    local x, y = cx - math.floor(w / 2), cy - math.floor(h * 0.56)
    local lines, s = fitLines(self:scene().lines, w - 14, { TITLE_SCALE, 2, 1 },
        math.max(1, math.floor((h - 10) / (Font.height * TITLE_SCALE + 4))))
    return x, y, w, h, lines, s
end

-- Writing on the page sits across the top of the eye, above the doodles, at
-- twice the 3x5 face wherever that still makes three lines. Both notes are laid
-- out in the one place, so the answer is written where the question was rubbed
-- out.
function Intro:note(game, text)
    local cx, cy, r = self:eye(game)
    local lines, s = fitLines({ text }, math.floor(r * 1.4), { 2, 1 }, 3)
    return lines, s, cx, cy - math.floor(r * 0.56), Font.height * s + s + 2
end

-- What is being written in this scene and where, for the screens that write
-- letter by letter: the board's chalk and the page's pencil. Both go down the
-- same way, so they are written, puffed and swished by the same code.
function Intro:lettering(game)
    local scene = self:scene()
    if scene.kind == "board" then
        local x, y, w, h, lines, s = self:board(game)
        local lineH = Font.height * s + s + 2
        return {
            lines = lines, s = s, lineH = lineH, cx = x + math.floor(w / 2),
            top = y + math.floor((h - (#lines * lineH - s - 2)) / 2),
            start = LEAD, step = WRITE_STEP, dust = Palette.graphite,
        }
    elseif scene.kind == "notebook" then
        local lines, s, cx, top, lineH = self:note(game, scene.write)
        return {
            lines = lines, s = s, lineH = lineH, cx = cx, top = top,
            start = scene.rub and LEAD + RUB_TIME + RUB_GAP or LEAD,
            step = PEN_STEP, dust = Palette.graphite,
        }
    end
end

-- The three doodles in the margin of the lesson's page, where a hand rests
-- when it is not taking notes: two blobs and a cool S.
function Intro:doodles(game)
    local cx, cy, r = self:eye(game)
    return {
        { sprite = Sprites.enemies.blob, x = cx - math.floor(r * 0.45), y = cy + math.floor(r * 0.36) },
        { sprite = Sprites.enemies.blob, x = cx - math.floor(r * 0.12), y = cy + math.floor(r * 0.52) },
        { sprite = Sprites.cools, x = cx + math.floor(r * 0.4), y = cy + math.floor(r * 0.3) },
    }
end

-- When the scene is finished saying what it says, and the next tap blinks.
function Intro:sceneEnd(game)
    local scene = self:scene()
    if scene.kind == "board" then
        local l = self:lettering(game)
        local _, t = typeTimes(l.lines, l.start, l.step)
        return t
    elseif scene.kind == "clock" then
        return TICK_LEAD + TICKS - 1 + 0.4
    elseif scene.kind == "notebook" then
        local l = self:lettering(game)
        local _, t = typeTimes(l.lines, l.start, l.step)
        if scene.doodle then t = math.max(t, LEAD + DOODLE_TIME * 3) end
        return t
    elseif scene.kind == "dark" then
        local _, t = typeTimes({ scene.say }, LEAD, DOT_STEP)
        return t
    end
    return 0
end

--- the eye -------------------------------------------------------------------

-- How shut the eye is, 0 open to 1 shut, and whether a shut eye is a slit or
-- the whole way. Only the opening and the dark are ever the whole way.
function Intro:closure()
    if self.wakeT < WAKE_DARK + WAKE_OPEN then
        return 1 - easeOut((self.wakeT - WAKE_DARK) / WAKE_OPEN), true
    end

    if self:scene().kind == "dark" then return 1, true end
    if self.blinkT and self:shutting() then
        return easeIn(self.blinkT / SHUT), true
    end

    if self.blinkT then
        local b = self.blinkT
        if b < BLINK_DOWN then return easeIn(b / BLINK_DOWN), false end
        b = b - BLINK_DOWN
        if b < BLINK_HOLD then return 1, false end
        return 1 - easeOut((b - BLINK_HOLD) / BLINK_UP), false
    end

    return 0, false
end

-- Whether the blink under way is the last one, into the dark, which closes the
-- whole way and does not come back up.
function Intro:shutting()
    local after = Intro.scenes[self.index + 1]
    return after ~= nil and after.kind == "dark"
end

-- The eye's two half-axes, in pixels.
function Intro:aperture(game)
    local _, _, r = self:eye(game)
    local c, full = self:closure()
    local rx = r * (1 - SQUASH_X * c)
    local ry = full and r * (1 - c) or SLIT + (r - SLIT) * (1 - c)
    return rx, ry
end

-- Ink everywhere outside the ellipse, a span each side of it per row. An
-- ellipse with no height left is a row of ink like any other.
local function drawLids(game, cx, cy, rx, ry)
    love.graphics.setColor(Palette.ink)
    for y = 0, game.vh - 1 do
        local dy = (y + 0.5 - cy) / math.max(ry, 0.001)
        if ry <= 0.5 or math.abs(dy) >= 1 then
            love.graphics.rectangle("fill", 0, y, game.vw, 1)
        else
            local half = rx * math.sqrt(1 - dy * dy)
            local l, r = math.floor(cx - half + 0.5), math.floor(cx + half + 0.5)
            if l > 0 then love.graphics.rectangle("fill", 0, y, l, 1) end
            if r < game.vw then love.graphics.rectangle("fill", r, y, game.vw - r, 1) end
        end
    end
end

--- skip ----------------------------------------------------------------------

-- The top corner's box on the other end of the top edge from the corner button,
-- so the left one stays where the title's settings button is about to be.
function Intro:skipBox(game)
    local label = I18n.t("SKIP")
    local w = Hud.footWidth(label)
    return game.vw - game.inset.r - Hud.CORNER_MARGIN - w,
        game.inset.t + Hud.CORNER_MARGIN, w, Hud.CORNER_SIZE, label
end

function Intro:skipAt(game, px, py)
    local x, y, w, h = self:skipBox(game)
    local pad = Input.usingTouch and 5 or 2
    return px >= x - pad and px <= x + w + pad and py >= y - pad and py <= y + h + pad
end

--- update --------------------------------------------------------------------

-- A tap anywhere but SKIP: finish what is being written, or blink on.
function Intro:advance()
    if self.leaving or self.blinkT then return end
    if self.wakeT < WAKE_DARK + WAKE_OPEN * 0.5 then return end

    if self.t < self.doneAt then
        self.t = self.doneAt
        return
    end

    if self.index == #Intro.scenes then
        self.leaving = true
        return
    end

    self.blinkT = 0
    self.swapped = false
end

-- Hands back "wake" on the frame the eye should open on the title, whether it
-- got there through the last scene or SKIP. Game:wake takes it from there.
function Intro:update(dt, game)
    self.clock = self.clock + dt
    self.wakeT = self.wakeT + dt
    self.t = self.t + dt

    local down = Input.pointerDown
    if down and not self.wasDown then
        if self:skipAt(game, Input.pointerX, Input.pointerY) then
            self.holding = true
        else
            self:advance()
        end
    end
    if not down then self.holding = false end
    self.wasDown = down

    -- The fill drains back faster than it fills, so a tap on SKIP shows a flicker
    -- of what holding it would do and then gets out of the way.
    if self.holding then
        self.hold = self.hold + dt
    else
        self.hold = math.max(0, self.hold - dt * 3)
    end
    if self.hold >= SKIP_HOLD then self.leaving = true end
    if self.leaving then return "wake" end

    if self.blinkT then
        self.blinkT = self.blinkT + dt
        local nextDark = self:shutting()
        local swapAt = nextDark and SHUT or BLINK_DOWN + BLINK_HOLD / 2

        if not self.swapped and self.blinkT >= swapAt then
            self.swapped = true
            self.index = self.index + 1
            self.t = 0
            self.written = 0
            self.passes = 0
            self.particles = Particles.new()
            -- Into the dark the lids have already closed for good, so the blink is
            -- over; anywhere else it still has the lift to play out.
            if nextDark then self.blinkT = nil end
        end
        if self.blinkT and self.blinkT >= BLINK_DOWN + BLINK_HOLD + BLINK_UP then
            self.blinkT = nil
        end
    end

    self.doneAt = self:sceneEnd(game)
    self:updateChalk(game)
    self:updateRub(game)
    self.particles:update(dt)
end

-- Dust off each letter as it lands, and a swish per line: the title's graphite
-- puff (src/menu.lua), off chalk on the board and pencil on the page. A tap that
-- finishes the writing writes the rest silently: a burst off every letter at
-- once is a cloud, not someone writing.
function Intro:updateChalk(game)
    local l = self:lettering(game)
    if not l then return end

    local lines, s = l.lines, l.s
    local times = typeTimes(lines, l.start, l.step)
    local target = countBy(times, self.t)
    local quiet = target - self.written > 2

    while self.written < target do
        self.written = self.written + 1

        -- Which line and letter the count has reached.
        local n, li = self.written, 1
        while li < #lines and n > Font.count(lines[li]) do
            n = n - Font.count(lines[li])
            li = li + 1
        end
        local line = lines[li]

        if not quiet then
            if n == 1 then
                local last = times[self.written + Font.count(line) - 1] or times[self.written]
                Sfx.play(Sfx.brushFor(math.max(0.2, last - times[self.written] + l.step)))
            end
            local lx = l.cx - math.floor(Font.width(line) * s / 2)
                + (n - 1) * Font.advance * s + s
            local ly = l.top + (li - 1) * l.lineH + Font.height * s / 2
            self.particles:burst(lx, ly, 2, l.dust)
        end
    end
end

-- Where the eraser is `f` of the way through rubbing out a block of lines: back
-- and forth across it RUB_PASSES times, working down it as it goes. Returns the
-- point and which way it is heading.
local function rubAt(lines, s, cx, top, lineH, f)
    local widest = 0
    for _, line in ipairs(lines) do widest = math.max(widest, Font.width(line) * s) end
    local h = #lines * lineH - s - 2

    local pass = math.min(RUB_PASSES - 1, math.floor(f * RUB_PASSES))
    local u = f * RUB_PASSES - pass
    local dir = pass % 2 == 0 and 1 or -1
    local x = cx + (u - 0.5) * (widest + 6) * dir
    local y = top + h * (pass + u) / RUB_PASSES
    return x, y, dir, pass
end

-- The question coming off the page: crumbs off the eraser every frame and a
-- brush swish at the top of each pass. A tap that jumps past the rub skips the
-- noise with it, the way a tap past the writing does.
function Intro:updateRub(game)
    local scene = self:scene()
    if not scene.rub then return end

    local f = (self.t - LEAD) / RUB_TIME
    if f < 0 or f >= 1 then
        if f >= 1 then self.passes = RUB_PASSES end
        return
    end

    local lines, s, cx, top, lineH = self:note(game, scene.rub)
    local x, y, dir, pass = rubAt(lines, s, cx, top, lineH, f)

    if pass >= self.passes then
        self.passes = pass + 1
        Sfx.play(Sfx.brushFor(RUB_TIME / RUB_PASSES))
    end

    local ink = Palette[scene.rubColor] or Palette.ink
    self.particles:crumb(x, y, dir, 0, 4, Palette.graphite)
    if love.math.random() < 0.5 then
        self.particles:crumb(x, y, dir, 0, 4, ink)
    end
end

function Intro:keypressed()
    self:advance()
end

--- draw ----------------------------------------------------------------------

local function wall(game)
    love.graphics.setColor(Palette.sky)
    love.graphics.rectangle("fill", 0, 0, game.vw, game.vh)
end

-- Lines of lettering, centred one under another, with `count` letters of the
-- whole block written so far.
local function printBlock(lines, cx, top, s, lineH, count, color, o)
    for i, line in ipairs(lines) do
        local n = Font.count(line)
        o.count = util.clamp(count, 0, n)
        o.seed = (o.seedBase or 0) + i * 17
        Scribble.printBig(line, cx, top + (i - 1) * lineH, s, color, o)
        count = count - n
    end
end

function Intro:drawBoard(game)
    wall(game)
    local x, y, w, h = self:board(game)

    -- The frame, the board, and a tray along the foot with a stick of chalk on it.
    love.graphics.setColor(Palette.slate)
    love.graphics.rectangle("fill", x - 3, y - 3, w + 6, h + 6)
    love.graphics.setColor(Palette.ink)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(Palette.graphite)
    love.graphics.rectangle("fill", x - 5, y + h + 3, w + 10, 3)
    love.graphics.setColor(Palette.paper)
    love.graphics.rectangle("fill", x + w - 22, y + h + 1, 6, 2)

    -- What the last lesson left on it: rubbed-out chalk, a smear here and there,
    -- the same on every board this morning.
    love.graphics.setColor(Palette.slate)
    for i = 1, 14 do
        local sx = x + 4 + math.floor(util.hash01(i, 3, 41) * (w - 18))
        local sy = y + 3 + math.floor(util.hash01(i, 7, 43) * (h - 6))
        love.graphics.rectangle("fill", sx, sy, 3 + math.floor(util.hash01(i, 5, 47) * 9), 1)
    end

    local l = self:lettering(game)
    local times = typeTimes(l.lines, l.start, l.step)

    printBlock(l.lines, l.cx, l.top, l.s, l.lineH, countBy(times, self.t),
        Palette.paper, { shadow = Palette.slate, wobble = true, t = self.clock,
            seedBase = self.index * 101 })
end

-- Seconds past midnight to the hands' three angles, in radians clockwise from
-- twelve. The second hand jumps a second at a time and the other two creep, so
-- the minute hand clicks over on the tick that ends the scene.
local function handAngles(secs)
    local s = secs % 60
    local m = (secs / 60) % 60
    local h = (secs / 3600) % 12
    local turn = math.pi * 2
    return h / 12 * turn, math.floor(m) / 60 * turn, s / 60 * turn
end

local function hand(cx, cy, a, len, width, tail)
    local dx, dy = math.sin(a), -math.cos(a)
    local x0, y0 = cx - dx * (tail or 0), cy - dy * (tail or 0)
    if width > 1 then
        pixelart.band(x0, y0, cx + dx * len, cy + dy * len, width)
    else
        pixelart.line(x0, y0, cx + dx * len, cy + dy * len)
    end
end

function Intro:drawClock(game)
    wall(game)
    local cx, cy, r = self:eye(game)
    local rc = math.floor(r * 0.78)

    love.graphics.setColor(Palette.ink)
    pixelart.circleFill(cx, cy, rc + 2)
    love.graphics.setColor(Palette.paper)
    pixelart.circleFill(cx, cy, rc)

    -- A dot every minute and a block every five, just inside the rim.
    for i = 0, 59 do
        local a = i / 60 * math.pi * 2
        local px = math.floor(cx + math.sin(a) * (rc - 3) + 0.5)
        local py = math.floor(cy - math.cos(a) * (rc - 3) + 0.5)
        if i % 5 == 0 then
            love.graphics.setColor(Palette.ink)
            love.graphics.rectangle("fill", px - 1, py - 1, 2, 2)
        else
            love.graphics.setColor(Palette.graphite)
            love.graphics.rectangle("fill", px, py, 1, 1)
        end
    end

    local s = rc >= 46 and 2 or 1
    local rn = rc - 6 - Font.height * s
    for n = 1, 12 do
        local a = n / 12 * math.pi * 2
        Scribble.printBig(tostring(n), cx + math.sin(a) * rn,
            cy - math.cos(a) * rn - Font.height * s / 2, s, Palette.ink, {})
    end

    -- The first tick lands TICK_LEAD in and one a second after it, so the
    -- TICKS-th is the one that turns the minute. A tap that finishes the scene
    -- early lands on that tick too (Intro:sceneEnd).
    local ticks = self.t >= TICK_LEAD and math.floor(self.t - TICK_LEAD) + 1 or 0
    local ha, ma, sa = handAngles(self:scene().at + ticks)

    love.graphics.setColor(Palette.ink)
    hand(cx, cy, ha, rc * 0.5, 3)
    hand(cx, cy, ma, rc * 0.76, 2)
    love.graphics.setColor(Palette.red)
    hand(cx, cy, sa, rc * 0.84, 1, rc * 0.16)

    love.graphics.setColor(Palette.ink)
    pixelart.circleFill(cx, cy, 2)
    love.graphics.setColor(Palette.red)
    love.graphics.rectangle("fill", cx, cy, 1, 1)
end

-- The lesson's own page, through the same pass the run draws it with, so the
-- doodles overprint the ruling the way pencil does. They are drawn on in the
-- scene that has them drawn, one after another, left to right.
function Intro:drawNotebook(game)
    local scene = self:scene()

    Overprint.beginPage()
    Background.drawAs(Subjects.default.key, 0, 0, game.vw, game.vh)
    Overprint.beginInk()

    love.graphics.setColor(1, 1, 1)
    for i, d in ipairs(self:doodles(game)) do
        local p = 1
        if scene.doodle then
            p = util.clamp((self.t - LEAD - (i - 1) * DOODLE_TIME) / DOODLE_TIME, 0, 1)
        end
        if p > 0 then
            local sp, k = d.sprite, DOODLE_SCALE
            local left, top = math.floor(d.x) - sp.ox * k, math.floor(d.y) - sp.oy * k
            love.graphics.setScissor(left, top, math.max(1, math.ceil(sp.w * k * p)), sp.h * k)
            sp:draw(d.x, d.y, false, k)
            love.graphics.setScissor()
        end
    end

    -- The note, in the same ink layer as the doodles: pencil on a ruled page,
    -- so a rule shows through it the way it shows through anything drawn here.
    if scene.rub then
        local f = util.clamp((self.t - LEAD) / RUB_TIME, 0, 1)
        if f < 1 then
            local lines, s, cx, top, lineH = self:note(game, scene.rub)
            printBlock(lines, cx, top, s, lineH, math.huge,
                Palette[scene.rubColor] or Palette.ink,
                { wobble = true, t = self.clock, seedBase = 7, dither = f })
        end
    end

    local l = self:lettering(game)
    local times = typeTimes(l.lines, l.start, l.step)
    printBlock(l.lines, l.cx, l.top, l.s, l.lineH, countBy(times, self.t),
        Palette[scene.color] or Palette.ink,
        { wobble = true, t = self.clock, seedBase = 7 })

    Overprint.finish()
end

-- The next-tap mark: a little arrow at the foot of the eye that blinks once the
-- scene has said its piece. Paper on an ink shadow, so it reads on the board,
-- the wall, the page and the dark alike.
function Intro:drawMore(game)
    if self.blinkT or self.t < self.doneAt or math.floor(self.clock * 2.5) % 2 == 1 then
        return
    end
    local cx, cy, r = self:eye(game)
    local y = cy + r - 9
    for i = 0, 3 do
        love.graphics.setColor(Palette.ink)
        love.graphics.rectangle("fill", cx - 3 + i, y + i + 1, 7 - i * 2, 1)
    end
    for i = 0, 2 do
        love.graphics.setColor(Palette.paper)
        love.graphics.rectangle("fill", cx - 2 + i, y + i, 5 - i * 2, 1)
    end
end

-- The button, filling with blush from the left for as long as it is held.
function Intro:drawSkip(game)
    local x, y, w, h, label = self:skipBox(game)
    local hot = self.hold > 0

    love.graphics.setColor(hot and Palette.red or Palette.slate)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(Palette.paper)
    love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2)

    local fill = math.floor((w - 2) * util.clamp(self.hold / SKIP_HOLD, 0, 1))
    if fill > 0 then
        love.graphics.setColor(Palette.blush)
        love.graphics.rectangle("fill", x + 1, y + 1, fill, h - 2)
    end

    love.graphics.setColor(hot and Palette.red or Palette.slate)
    Font.print(label, x + math.floor((w - Font.width(label)) / 2),
        y + math.floor((h - Font.height) / 2))
end

function Intro:draw(game)
    local scene = self:scene()
    if scene.kind == "board" then
        self:drawBoard(game)
    elseif scene.kind == "clock" then
        self:drawClock(game)
    elseif scene.kind == "notebook" then
        self:drawNotebook(game)
    end
    self.particles:draw()

    local cx, cy = self:eye(game)
    drawLids(game, cx, cy, self:aperture(game))

    -- Typed into the dark, so on top of the lids rather than through them.
    if scene.kind == "dark" and not self.blinkT then
        local times = typeTimes({ scene.say }, LEAD, DOT_STEP)
        Scribble.printBig(scene.say, cx, cy - math.floor(Font.height * TITLE_SCALE / 2),
            TITLE_SCALE, Palette.paper, { count = countBy(times, self.t) })
    end

    self:drawMore(game)
    self:drawSkip(game)
end

--- the last opening ----------------------------------------------------------

-- The eye opening on the title. Handed back to Game as its own small object
-- because the title is the state by then: the title updates and draws as it
-- always does, and this only lays the lids over it until they are off the
-- screen. It starts from however open the eye was when it was left, so a SKIP
-- held mid-scene widens the eye that was already there.
local Wake = {}
Wake.__index = Wake

function Intro:wake(game)
    local _, _, r = self:eye(game)
    local rx, ry = self:aperture(game)
    return setmetatable({ t = 0, fx = rx / r, fy = ry / r }, Wake)
end

function Wake:radii(game)
    local cx, cy, r = Intro:eye(game)
    local open = REVEAL_OPEN * (1 - math.min(self.fx, self.fy))
    if self.t < open then
        local f = easeOut(self.t / open)
        return r * util.lerp(self.fx, 1, f), r * util.lerp(self.fy, 1, f)
    end

    local far = util.len(math.max(cx, game.vw - cx), math.max(cy, game.vh - cy)) + 2
    local f = easeIn((self.t - open - REVEAL_HOLD) / REVEAL_WIDE)
    local rr = util.lerp(r, far, f)
    return rr, rr, f >= 1
end

-- True once the lids are off every edge of the screen.
function Wake:update(dt, game)
    self.t = self.t + dt
    local _, _, done = self:radii(game)
    return done
end

function Wake:draw(game)
    local cx, cy = Intro:eye(game)
    local rx, ry = self:radii(game)
    drawLids(game, cx, cy, rx, ry)
end

return Intro
