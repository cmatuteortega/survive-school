-- Worksheets: the little puzzles printed on the page, which pay a run for
-- stopping to solve one while the horde keeps coming (WORKSHEETS.md is the
-- idea list, README **Worksheets on the page** the argument).
--
-- Each a row or more in KINDS:
--
-- - **Tic-tac-toe**, on every page. A game already in play -- red O's, black
--   X's -- with one cell that finishes three X's in a row. Scribble a cross into
--   it and the line is drawn through the three and a coin drops. Scribble into
--   any other cell and the page plays its O where yours should have gone.
-- - **The pop quiz**, on MATHS. A question on a board and three answers ruled
--   out under it (src/quiz.lua). Stand on one until the circle round it has
--   finished drawing: right is a diamond, wrong is a giant walking in off the
--   ring (Spawner:giant) and the right answer circled for next time.
-- - **The sequence**, on MATHS too: the same board with a run of numbers and
--   the next one missing. Right is a heart, wrong is twenty off the bar.
-- - **A board of the lesson's own** on SCIENCE, FINANCE and MUSIC: the pop
--   quiz's board asking out of that subject's book -- equations, prices,
--   notes -- and paying the way its row in BOARDS says.
-- - **Simon says**, on MUSIC. A hand bell and four notes: ring the bell by
--   walking onto it or drawing over it, hear a tune, and walk the notes in the
--   same order. Right is a heart; three wrong notes and the sheet fades away.
-- - **The dodgeball pit**, on P.E. A block of the calendar's own day boxes:
--   walk in and the class is thrown at you. Last the clock untouched and
--   inside for a diamond; a hit or a step out and the sheet fades away.
-- - **Hopscotch**, on P.E. too: a numbered path of day boxes to step along in
--   order against a clock, for a heart; a wrong box or the clock and it fades.
-- - **The circuit**, on SCIENCE. A battery, bulbs and bare printed wire with
--   gaps in it: draw a wire across so the ringed bulbs light, without shorting
--   the battery or lighting another, for a wall clock.
-- - **Join the dots**, on ART. Numbered dots touched with the pen in order
--   make a picture, for a gold star; out of order three times and they wander.
-- - **The portrait**, on ART too. Stand on the chalk cross by the easel and do
--   not move while your portrait is painted, for an alarm clock at your feet.
-- - **The market**, on FINANCE. A price chart against a clock and a BUY and a
--   SELL box: real coins in, and out again at whatever the price is then.
-- - **Hangman**, on GRAMMAR. A word with three letters out and more letters
--   than it needs to stand on, the boards' way. Three right is a diamond; three
--   wrong hangs the man on the gallows, who climbs down and comes for you, and
--   is a heart if you put him down.
--
-- They are placed the way the fixed pickups are (src/pickup.lua): a pure
-- function of the cell and the run's seed, one in a fraction of a coarser
-- grid, materialising as you come near. Unlike a pickup a worksheet is never
-- dropped when you walk off -- it has state (half a cross, a circle half drawn,
-- an answer given) and a sheet you came back to should be the sheet you left --
-- so the list only grows, by one every few hundred pixels walked, and only the
-- sheets near you are updated.
--
-- Nothing here reads handwriting. A cross is *ground covered* inside a cell,
-- on a 2px grid, the rule src/scribble.lua answers every question in the book
-- by; an answer is a place you stand, a row of places walked in order, or the
-- copper and the dots a line drawn across the sheet touched. All four are
-- things the game already asks you to do with your hands, so a worksheet is a
-- new question, not a new control.

local Palette = require("src.palette")
local Pickup = require("src.pickup")
local Quiz = require("src.quiz")
local Input = require("src.input")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local Sprites = require("src.sprites")
local Font = require("src.font")
local I18n = require("src.i18n")
local Purse = require("src.purse")
local util = require("src.util")

local Worksheet = {}

-- What a sheet that pays a heart or a diamond actually pays, and the colour it
-- bursts in. Below a master's it is what the sheet says; at the top two rungs
-- it is a diamond or a star, always (`prize` on the course's row,
-- src/course.lua) -- a heart is not worth a stop with the horde at twice the
-- health, and a sheet nobody stops for is a sheet that is not there. Coins are
-- left alone: they are the purse's, and the course already pays it at its rate.
local GLINT = {
    heart = Palette.red, diamond = Palette.sky, star = Palette.red,
}

function Worksheet.prize(game, kind)
    local better = game.course and game.course.prize
    if better and (kind == "heart" or kind == "diamond") then
        kind = better[love.math.random(#better)]
    end
    return kind, GLINT[kind]
end

-- Put down where it was won, through the course's say on what it is.
local function award(game, kind, x, y)
    local colour
    kind, colour = Worksheet.prize(game, kind)
    game.pickups[#game.pickups + 1] = Pickup.new(kind, x, y)
    game.particles:burst(x, y, 10, colour)
end

-- How a sheet tells you it is won or lost: the word thrown up over the sheet
-- in the multikill's bold face (src/multikill.lua), red on ink, where your
-- eyes already are -- the notice line at the foot of the screen is for what a
-- sheet says while it is under way, and a verdict read down there is a verdict
-- read late. In the book's own two colours for right and wrong: blue, the
-- ring round a right answer, for a sheet won, and red, the line through a
-- wrong one, for a sheet lost. Guarded, for a page without the multikill (a
-- test harness).
local function shout(game, text, x, y, colour)
    if game.multikill then
        game.multikill:shout(text, x, y, colour)
    else
        game:say(text)
    end
end

-- Coarser than the pickups' 260 and sparser: a worksheet is an event you turn
-- for, and a page tiled in them would be a page of homework.
local CELL = 520
local DENSITY = 0.4
local MATERIALIZE = 440
local ACTIVE = 260      -- only sheets this near are updated
local CLEAR_START = 200 -- none on the spot a run begins on
local PAD = 10          -- pickups keep this far off a sheet's footprint

-- What each page prints, by weight. A subject row may carry `worksheets` of
-- its own (src/subjects.lua: MATHS); everything else plays tic-tac-toe.
local DEFAULT_MIX = { tictactoe = 1 }

local function kindFor(mix, roll)
    local keys, total = {}, 0
    for k, w in pairs(mix) do keys[#keys + 1] = k; total = total + w end
    table.sort(keys) -- pairs() has no order, and the layout must not move
    roll = roll * total
    for _, k in ipairs(keys) do
        roll = roll - mix[k]
        if roll <= 0 then return k end
    end
    return keys[1]
end

--- tic-tac-toe -------------------------------------------------------------------

local T = {}
T.__index = T

local SIZE = 14             -- one cell of the grid
local HALF = SIZE * 3 / 2
local COVER_CELL = 2
-- More than src/scribble.lua's six, because this box is on the page you fight
-- on: a stroke aimed at a blob that clips a corner of the grid must not be read
-- as an answer. One pass through a cell covers about six; a cross is two.
local COVER_MIN = 10
local COVER_FORGET = 1      -- seconds without ink before a cell's marks go
local CROSS_TIME = 0.25
local LINE_TIME = 0.4

local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
    { 1, 5, 9 }, { 3, 5, 7 },
}

local function three(cells, mark)
    for _, l in ipairs(LINES) do
        if cells[l[1]] == mark and cells[l[2]] == mark and cells[l[3]] == mark then
            return l
        end
    end
end

-- A game in progress, three moves each, X to play and win. Built from the
-- winning line outwards -- two X's on it and its third cell empty -- and the
-- other six dealt three O's, one more X and two blanks, rerolled until the O's
-- have not already won. A blank off the line can win too, now and then; that
-- is a second right answer and is allowed to be.
local function deal()
    for _ = 1, 50 do
        local line = LINES[love.math.random(#LINES)]
        local gap = line[love.math.random(3)]
        local cells = {}
        for _, i in ipairs(line) do
            if i ~= gap then cells[i] = "x" end
        end

        local rest = {}
        for i = 1, 9 do
            if not (i == line[1] or i == line[2] or i == line[3]) then
                rest[#rest + 1] = i
            end
        end
        for i = #rest, 2, -1 do
            local j = love.math.random(i)
            rest[i], rest[j] = rest[j], rest[i]
        end
        cells[rest[1]], cells[rest[2]], cells[rest[3]] = "o", "o", "o"
        cells[rest[4]] = "x"

        if not three(cells, "o") then return cells, gap end
    end
end

function T.new(x, y)
    local cells, gap = deal()
    return setmetatable({
        kind = "tictactoe",
        x = x, y = y,
        hw = HALF, hh = HALF,
        cells = cells, gap = gap,
        cover = {},
        state = "open",
        seed = util.hash01(x, y, 3) * 1000,
    }, T)
end

function T:cellCentre(i)
    local gx, gy = (i - 1) % 3, math.floor((i - 1) / 3)
    return self.x - HALF + (gx + 0.5) * SIZE, self.y - HALF + (gy + 0.5) * SIZE
end

-- Which cell a page point is in, held a pixel in from the rules so a line
-- drawn along one does not count for both sides of it.
function T:cellAt(px, py)
    local lx, ly = px - (self.x - HALF), py - (self.y - HALF)
    if lx < 0 or ly < 0 or lx >= SIZE * 3 or ly >= SIZE * 3 then return end
    local ix, iy = lx % SIZE, ly % SIZE
    if ix < 1 or iy < 1 or ix > SIZE - 1 or iy > SIZE - 1 then return end
    return math.floor(ly / SIZE) * 3 + math.floor(lx / SIZE) + 1
end

function T:ink(px, py)
    local i = self:cellAt(px, py)
    if not i or self.cells[i] then return end

    local key = math.floor(px / COVER_CELL) * 65536 + math.floor(py / COVER_CELL)
    local c = self.cover[i]
    if not c then c = { n = 0, keys = {}, marks = {} }; self.cover[i] = c end
    c.idle = 0
    if c.keys[key] then return end
    c.keys[key] = true
    c.n = c.n + 1
    c.marks[#c.marks + 1] = { x = math.floor(px), y = math.floor(py) }
    if c.n >= COVER_MIN then return i end
end

function T:commit(i, game)
    self.cells[i] = "x"
    self.played = i
    self.cover = {}
    self.t = 0
    self.line = three(self.cells, "x")
    if self.line then
        self.state = "crossing"
        Sfx.play("tick")
    else
        -- The page plays where you should have.
        self.cells[self.gap] = "o"
        self.blocked = self.gap
        self.state = "lost"
        shout(game, "BLOCKED!", self.x, self.y - HALF - 2, Palette.red)
        Sfx.play("stamp")
    end
end

function T:update(dt, game, pen)
    if self.state == "open" then
        if pen then
            local x0, y0 = self.penX or pen.x, self.penY or pen.y
            local dx, dy = pen.x - x0, pen.y - y0
            local steps = math.max(1, math.ceil(util.len(dx, dy)))
            for s = 0, steps do
                local hit = self:ink(x0 + dx * s / steps, y0 + dy * s / steps)
                if hit then self:commit(hit, game) break end
            end
            self.penX, self.penY = pen.x, pen.y
        else
            self.penX, self.penY = nil, nil
        end
        -- A cell left alone forgets a cross it never finished: a cross is two
        -- strokes a moment apart, three grazes a minute apart are not one.
        for i, c in pairs(self.cover) do
            c.idle = c.idle + dt
            if c.idle > COVER_FORGET then self.cover[i] = nil end
        end
        return
    end

    self.t = (self.t or 0) + dt
    if self.state == "crossing" and self.t >= CROSS_TIME + LINE_TIME then
        self.state = "won"
        -- Under the grid rather than on it, so the line it paid for stays read.
        local cy = self.y + HALF + 8
        game.pickups[#game.pickups + 1] = Pickup.new("coin", self.x, cy)
        game.particles:burst(self.x, cy, 10, Palette.blush)
        shout(game, "THREE IN A ROW", self.x, self.y - HALF - 2, Palette.blue)
        Sfx.play("accept")
    end
end

local function drawCross(cx, cy, p)
    local a = util.clamp(p * 2, 0, 1)
    local b = util.clamp(p * 2 - 1, 0, 1)
    if a > 0 then
        pixelart.band(cx - 4, cy - 4, cx - 4 + 8 * a, cy - 4 + 8 * a, 2)
    end
    if b > 0 then
        pixelart.band(cx + 4, cy - 4, cx + 4 - 8 * b, cy - 4 + 8 * b, 2)
    end
end

function T:draw()
    local x0, y0 = math.floor(self.x - HALF), math.floor(self.y - HALF)

    -- The rules, a pixel off true here and there the way a ruled-by-hand grid
    -- is, and fixed: this is something you aim at.
    love.graphics.setColor(Palette.slate)
    for k = 1, 2 do
        local o = k * SIZE
        local w = util.hash01(self.seed, k, 1) > 0.5 and 1 or 0
        love.graphics.rectangle("fill", x0 + o + w, y0 - 1, 1, SIZE * 3 + 2)
        love.graphics.rectangle("fill", x0 - 1, y0 + o - w, SIZE * 3 + 2, 1)
    end

    for i = 1, 9 do
        local cx, cy = self:cellCentre(i)
        if self.cells[i] == "o" then
            love.graphics.setColor(Palette.red)
            pixelart.circleOutline(cx, cy, 4)
            if i == self.blocked then pixelart.circleOutline(cx, cy, 3) end
        elseif self.cells[i] == "x" then
            love.graphics.setColor(Palette.ink)
            local p = 1
            if i == self.played then p = util.clamp(self.t / CROSS_TIME, 0, 1) end
            drawCross(cx, cy, p)
        end
    end

    love.graphics.setColor(Palette.graphite)
    for _, c in pairs(self.cover) do
        for _, m in ipairs(c.marks) do
            love.graphics.rectangle("fill", m.x, m.y, 1, 1)
        end
    end

    -- Struck through, end to end and a little past, as fast as a pen would.
    if self.line and self.t and self.t > CROSS_TIME then
        local p = util.clamp((self.t - CROSS_TIME) / LINE_TIME, 0, 1)
        local ax, ay = self:cellCentre(self.line[1])
        local bx, by = self:cellCentre(self.line[3])
        local ux, uy = util.normalize(bx - ax, by - ay)
        ax, ay = ax - ux * 5, ay - uy * 5
        bx, by = bx + ux * 5, by + uy * 5
        love.graphics.setColor(Palette.ink)
        pixelart.band(ax, ay, ax + (bx - ax) * p, ay + (by - ay) * p, 2)
    end
end

--- the pop quiz ------------------------------------------------------------------

local Q = {}
Q.__index = Q

local SPACING = 44      -- between answer centres
local BOARD_UP = 20     -- the board's middle, above the sheet's
local ANSWERS_DOWN = 14 -- the answers' line, below it
local HOLD = 1.5        -- seconds stood on an answer to give it
local DRAIN = 2         -- how much faster a circle undraws than draws
local RY = 7

-- A wrong sequence costs this much health, through the one door every hit
-- comes in by (Player:hurt), so it shakes and buzzes like being bitten.
local SEQUENCE_HURT = 20

-- What a board can pay and charge. Three prizes and two prices, shared out
-- between the boards below so that each lesson's says something about it.
local function drop(kind)
    return function(game, x, y) award(game, kind, x, y) end
end

-- Three coins in a row under the answer, into the purse like tic-tac-toe's.
local function coins(game, x, y)
    for k = -1, 1 do
        game.pickups[#game.pickups + 1] = Pickup.new("coin", x + k * 9, y)
    end
    game.particles:burst(x, y, 10, Palette.blush)
end

local function giant(game)
    game.spawner:giant(game)
end

-- Through the invulnerability window rather than lost to it: a wrong answer
-- given a moment after a blob bit you still costs the twenty.
local function sting(game)
    local p = game.player
    p.invuln = 0
    p:hurt(SEQUENCE_HURT)
end

-- The boards that are answered by standing: which book of questions each asks
-- out of (src/quiz.lua) and what it pays. They share everything else -- the
-- board, the three answers, the circle that draws while you stand -- so a new
-- one is a row.
--
-- The pop quiz is the high-stakes one: a whole level, or a giant. The sequence
-- is the low one, and pays in the same coin both ways: health. A heart for the
-- right answer and twenty off the bar for the wrong one, so a run low on
-- health is taking a real gamble on a board it could just walk past.
--
-- The other lessons take one each and say which kind of gamble they are.
-- SCIENCE is the quiz's: an experiment that goes wrong grows something. FINANCE
-- pays the purse, three coins against a giant, the one board whose prize
-- outlives the run. MUSIC is the sequence's, a heart against a sting -- a wrong
-- note hurts.
local BOARDS = {
    quiz = { book = Quiz.byCourse, right = drop("diamond"), wrong = giant },
    sequence = { book = Quiz.sequences, right = drop("heart"), wrong = sting },
    science = { book = Quiz.science, right = drop("diamond"), wrong = giant },
    finance = { book = Quiz.finance, right = coins, wrong = giant },
    music = { book = Quiz.music, right = drop("heart"), wrong = sting },
}

function Q.new(x, y, courseKey, kind)
    local row = BOARDS[kind]
    local quiz = Quiz.new(courseKey, row.book)
    local q = setmetatable({
        kind = kind,
        row = row,
        x = x, y = y,
        quiz = quiz,
        board = Quiz.layout(quiz.q),
        answers = {},
        state = "open",
        seed = util.hash01(x, y, 4) * 1000,
    }, Q)

    for i, a in ipairs(quiz.answers) do
        local lay = Quiz.layout(a)
        q.answers[i] = {
            lay = lay,
            x = x + (i - 2) * SPACING,
            y = y + ANSWERS_DOWN,
            rx = math.max(9, math.floor(lay.w / 2) + 5),
            hold = 0,
        }
    end

    q.bw = math.max(q.board.w + 12, SPACING * 2)
    q.bh = q.board.bottom - q.board.top + 10
    q.hw = math.max(q.bw / 2, SPACING + q.answers[3].rx)
    q.hh = math.max(BOARD_UP + q.bh / 2 + 2, ANSWERS_DOWN + RY + 2)
    return q
end

function Q:standingOn(px, py)
    for i, a in ipairs(self.answers) do
        local dx, dy = (px - a.x) / a.rx, (py - a.y) / RY
        if dx * dx + dy * dy <= 1 then return i end
    end
end

function Q:update(dt, game)
    if self.state ~= "open" then return end

    local on = self:standingOn(game.player.x, game.player.y)
    for i, a in ipairs(self.answers) do
        if i == on then
            a.hold = a.hold + dt / HOLD
        else
            a.hold = math.max(0, a.hold - dt * DRAIN / HOLD)
        end
    end

    if on and self.answers[on].hold >= 1 then
        self.state = "done"
        self.chosen = on
        if on == self.quiz.right then
            -- Just above the answer you are standing on, between it and the
            -- board: a step away, so taking it is a thing you do and the
            -- question it paid for is not hidden under it.
            self.row.right(game, self.answers[on].x, self.y - 2)
            shout(game, "CORRECT!", self.x, self.y - BOARD_UP - self.bh / 2 - 2, Palette.blue)
            Sfx.play("accept")
        else
            self.row.wrong(game)
            game.particles:burst(self.answers[on].x, self.answers[on].y, 10, Palette.red)
            shout(game, "WRONG ANSWER", self.x, self.y - BOARD_UP - self.bh / 2 - 2, Palette.red)
            Sfx.play("stamp")
        end
    end
end

-- A hand-drawn ring round an answer, laid clockwise from twelve o'clock as far
-- as `p` has got: two pixels thick, the second ring a pixel out.
local function ring(cx, cy, rx, ry, p, dotted)
    local n = math.floor(2 * math.pi * math.max(rx, ry) * 1.5)
    local last = math.floor(n * util.clamp(p, 0, 1))
    for k = 0, last - 1 do
        if not dotted or k % 4 == 0 then
            local a = -math.pi / 2 + 2 * math.pi * k / n
            local c, s = math.cos(a), math.sin(a)
            love.graphics.rectangle("fill",
                math.floor(cx + c * rx + 0.5), math.floor(cy + s * ry + 0.5), 1, 1)
            if not dotted then
                love.graphics.rectangle("fill",
                    math.floor(cx + c * (rx + 1) + 0.5),
                    math.floor(cy + s * (ry + 1) + 0.5), 1, 1)
            end
        end
    end
end

function Q:draw()
    -- The board: a box ruled round the question, the question in ink.
    local bx = math.floor(self.x - self.bw / 2)
    local by = math.floor(self.y - BOARD_UP - self.bh / 2)
    love.graphics.setColor(Palette.slate)
    love.graphics.rectangle("fill", bx, by, self.bw, 1)
    love.graphics.rectangle("fill", bx, by + self.bh - 1, self.bw, 1)
    love.graphics.rectangle("fill", bx, by, 1, self.bh)
    love.graphics.rectangle("fill", bx + self.bw - 1, by, 1, self.bh)
    love.graphics.rectangle("fill", bx + 1, by + self.bh, self.bw - 1, 1)

    love.graphics.setColor(Palette.ink)
    Quiz.print(self.board, self.x - self.board.w / 2, by + 5 - self.board.top)

    local right = self.quiz.right
    for i, a in ipairs(self.answers) do
        local lay = a.lay
        local tx = a.x - lay.w / 2
        local ty = a.y - math.floor((lay.bottom + lay.top) / 2)
        love.graphics.setColor(self.chosen and i ~= self.chosen and i ~= right
            and Palette.graphite or Palette.ink)
        Quiz.print(lay, tx, ty)

        if self.state == "open" then
            -- Where to stand, dotted, and how long you have stood there.
            love.graphics.setColor(Palette.graphite)
            ring(a.x, a.y, a.rx, RY, 1, true)
            if a.hold > 0 then
                love.graphics.setColor(Palette.blue)
                ring(a.x, a.y, a.rx, RY, a.hold)
            end
        elseif i == self.chosen and i ~= right then
            -- Yours, circled and struck out.
            love.graphics.setColor(Palette.red)
            ring(a.x, a.y, a.rx, RY, 1)
            pixelart.band(tx - 2, a.y + 2, tx + lay.w + 2, a.y - 2, 1)
        elseif i == right then
            love.graphics.setColor(Palette.blue)
            ring(a.x, a.y, a.rx, RY, 1)
        end
    end
end

--- simon says --------------------------------------------------------------------

-- A hand bell and four notes written on the page's own staves. Ring the bell --
-- walk onto it or draw over it -- and it plays a tune on the four, each note
-- jumping as it sounds; then walk the notes back in the same order, each one
-- circled as you get it right. Right to the end is a heart. A wrong note sounds
-- sour and starts you over, and the third one fades the whole sheet off the
-- page. Nothing else is lost: a failed Simon costs the heart you did not get,
-- which is the price of a sheet that asked nothing of you but your ears and a
-- few seconds.
--
-- It is the third way a sheet is answered -- not standing still, not drawing,
-- but walking through places in an order -- so where things go is the rule.
-- The notes are spread over a screen's worth of page, each on a stave of its
-- own, but dealt so that the straight walk between any two of them, or from
-- the bell to any of them, passes clear of every other note and of the bell: a
-- tune can always be walked without striking something it did not ask for, and
-- walking it never rings the bell and wipes your answer.
--
-- It is written in the page's notation rather than drawn over it. MUSIC's
-- paper is staves already (src/subjects.lua, STAVES), so a note is a head and
-- a stem put on one of them, where that pitch really sits -- D, E, G and A, out
-- of the pentatonic so any tune dealt off them is a tune -- and higher on a
-- stave is higher in the ear, for a player who reads music. All four sit under
-- the middle line, which is what lets their stems go up as a stave writes them:
-- a stem hanging off the left of a head this small reads as a flag.
--
-- It shows as well as sounds, because plenty of phones are played on mute and
-- the tune is the whole puzzle: a sounding note jumps off its line and throws
-- a ring out round itself.

local S = {}
S.__index = S

local SPREAD_X, SPREAD_Y = 100, 50 -- how far from the sheet's middle things go
local APART = 40      -- the least room between any two of them
local CLEAR = 15      -- how far every walk between two stays off a third
local NOTE_R = 9      -- a note's ring: where you stand to strike it
local BELL_RX, BELL_RY = 8, 8
local LEAD = 0.35     -- the bell swings this long before the first note
local BEAT = 0.42     -- one note of the tune
local LIT = 0.3       -- how long a note shows it is sounding, of its beat
local HOP = 4         -- how high a sounding note jumps off its stave
local RIPPLE = 5      -- how far the ring round a sounding note spreads
local CIRCLE = 0.3    -- seconds to scribble a ring round a note you got right
local FLASH = 0.45    -- how long a wrong note stays red
local TRIES = 3
local FADE = 1.2

-- What STAVES is, for the page that has no staves of its own to read.
local STAFF = { every = 40, line = 4, bar = 24 }
local BAR_EVERY = 192

-- Semitones off G (src/sfx/note.mp3 is struck at G, in the middle of the four
-- so no note is pitched far enough to drag -- and two octaves over the G4 the
-- stave writes, as a glockenspiel sounds, for src/sfx.lua's reason), and the
-- step each sits on, counted up from the stave's middle line (B4): half a line
-- apart apiece.
local NOTES = {
    { semis = -5, step = -5 }, -- D, the space under the bottom line
    { semis = -3, step = -4 }, -- E, the bottom line
    { semis = 0, step = -2 },  -- G, the second line
    { semis = 2, step = -1 },  -- A, the second space
}

-- How long the tune is, by course: a note more for every rung, so a doctorate
-- is copying six -- still well inside the few seconds a sheet may ask for.
local TUNE = { school = 3, bachelor = 4, masters = 5, phd = 6 }

local function ratio(semis) return 2 ^ (semis / 12) end

-- A tune never strikes one note twice running: a repeat would ask you to step
-- off a note and back on, which is a stumble, not a melody.
local function compose(n)
    local tune, last = {}, nil
    for i = 1, n do
        local k
        repeat k = love.math.random(#NOTES) until k ~= last
        tune[i], last = k, k
    end
    return tune
end

-- How far a point is from the walk between two others.
local function offPath(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = util.clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return util.len(px - (ax + dx * t), py - (ay + dy * t))
end

-- Every spot (the four notes and the bell) at least APART from every other,
-- and every walk between two of them at least CLEAR of every third.
local function fair(spots)
    for i = 1, #spots do
        for j = i + 1, #spots do
            local a, b = spots[i], spots[j]
            if util.len(a.x - b.x, a.y - b.y) < APART then return false end
            for k = 1, #spots do
                if k ~= i and k ~= j and offPath(spots[k].x, spots[k].y,
                    a.x, a.y, b.x, b.y) < CLEAR then
                    return false
                end
            end
        end
    end
    return true
end

-- Deal the four notes onto staves round (x, y) and the bell somewhere among
-- them, until the layout is fair. Each note goes on a stave of the page and at
-- its own pitch on it, never on a bar line, so its y is not free: it is the
-- stave's top line plus where that note is written.
local function deal(x, y, staff)
    local mid = staff.line * 2 -- the middle line, off the stave's top
    for _ = 1, 1000 do
        local spots = {}
        for i, n in ipairs(NOTES) do
            local top = math.floor((y + (love.math.random() * 2 - 1) * SPREAD_Y)
                / staff.every) * staff.every
            local nx
            repeat
                nx = math.floor(x + (love.math.random() * 2 - 1) * SPREAD_X)
            until math.abs((nx % BAR_EVERY) - staff.bar) > 6
            -- The head's middle; the spot you stand on sits up the stem a
            -- little, on the middle of the whole note.
            local hy = top + mid - n.step * staff.line / 2
            spots[i] = { x = nx, y = hy - 3, hy = hy }
        end
        spots[#NOTES + 1] = {
            x = math.floor(x + (love.math.random() * 2 - 1) * SPREAD_X),
            y = math.floor(y + (love.math.random() * 2 - 1) * SPREAD_Y),
        }
        if fair(spots) then return spots end
    end
end

function S.new(x, y, courseKey, staff)
    staff = staff or STAFF
    local spots = deal(x, y, staff)
    if not spots then return end
    local bell = table.remove(spots)
    local s = setmetatable({
        kind = "simon",
        x = x, y = y,
        hw = SPREAD_X + NOTE_R + RIPPLE + 2,
        hh = SPREAD_Y + staff.every + NOTE_R + RIPPLE + 2,
        bell = bell,
        pads = spots,
        tune = compose(TUNE[courseKey] or TUNE.school),
        state = "idle",
        tries = TRIES,
        lit = {},
        circled = {},
        seed = util.hash01(x, y, 5) * 1000,
    }, S)
    return s
end

function S:padAt(px, py)
    for i, p in ipairs(self.pads) do
        if util.len(px - p.x, py - p.y) <= NOTE_R then return i end
    end
end

-- Spread out, the sheet keeps pickups off its notes and its bell rather than
-- off the whole stretch of page it spans (Worksheet.covers).
function S:covers(x, y, pad)
    local r = NOTE_R + pad
    if math.abs(x - self.bell.x) < BELL_RX + pad
        and math.abs(y - self.bell.y) < BELL_RY + pad then
        return true
    end
    for _, p in ipairs(self.pads) do
        if util.len(x - p.x, y - p.y) < r then return true end
    end
    return false
end

function S:sound(i)
    Sfx.play("note", ratio(NOTES[i].semis))
    self.lit[i] = LIT
end

function S:ring()
    self.state = "playing"
    self.t = 0
    self.beat = 0
    self.pos = 1
    self.circled = {}
end

-- The note and the one a semitone over it, struck together: the one interval
-- no tune off a pentatonic can make, so it can only be a mistake.
function S:sour(i)
    local r = ratio(NOTES[i].semis)
    Sfx.play("note", r)
    Sfx.play("note", r * ratio(1))
    self.flash, self.flashT = i, FLASH
end

function S:step(i, game)
    if self.state == "idle" then
        -- Before the bell the notes are an instrument: playing them is how you
        -- find out they play, and none of it counts.
        self:sound(i)
        return
    end
    if self.state ~= "answer" then return end

    if self.tune[self.pos] == i then
        self:sound(i)
        self.circled[i] = self.circled[i] or 0
        self.pos = self.pos + 1
        if self.pos > #self.tune then
            self.state = "won"
            -- A step above the last note rather than on it, so taking it is a
            -- thing you do (the boards' reason).
            local p = self.pads[i]
            award(game, "heart", p.x, p.y - 18)
            shout(game, "BRAVO!", p.x, p.y - 24, Palette.blue)
            Sfx.play("accept")
        end
    else
        self:sour(i)
        self.tries = self.tries - 1
        self.pos = 1
        self.circled = {}
        if self.tries <= 0 then
            self.state = "fading"
            self.t = 0
            local p = self.pads[i]
            shout(game, "OUT OF TUNE!", p.x, p.y - 12, Palette.red)
        end
    end
end

function S:update(dt, game, pen)
    for i, l in pairs(self.lit) do
        self.lit[i] = l > dt and l - dt or nil
    end
    for i, c in pairs(self.circled) do
        self.circled[i] = math.min(1, c + dt / CIRCLE)
    end
    if self.flashT then
        self.flashT = self.flashT - dt
        if self.flashT <= 0 then self.flash, self.flashT = nil, nil end
    end

    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= FADE then self.state = "gone" end
        return
    end
    if self.state == "won" or self.state == "gone" then return end

    if self.state == "playing" then
        self.t = self.t + dt
        local k = math.floor((self.t - LEAD) / BEAT) + 1
        if k > self.beat and k >= 1 then
            self.beat = k
            if k <= #self.tune then
                self:sound(self.tune[k])
            else
                self.state = "answer"
            end
        end
    end

    -- Things happen as you arrive on them, not while you stand there: a note
    -- is struck once by stepping on it, and struck again by stepping off and on.
    local p = game.player
    local on = self:padAt(p.x, p.y)
    if on and on ~= self.on then self:step(on, game) end
    self.on = on

    local b = self.bell
    local dx, dy = (p.x - b.x) / BELL_RX, (p.y - b.y) / BELL_RY
    local bell = dx * dx + dy * dy <= 1
    local drawn = pen and math.abs(pen.x - b.x) <= BELL_RX
        and math.abs(pen.y - b.y) <= BELL_RY
    if (bell and not self.onBell) or (drawn and not self.penBell) then
        -- Not over a tune already playing; any other time it starts the tune
        -- again, and your answer with it.
        if self.state ~= "playing" then self:ring() end
    end
    self.onBell, self.penBell = bell, drawn
end

-- The fade, the way every fade in the book goes: each colour a step down its
-- ramp, and the stamps dropping out at random a pixel at a time.
local FADED = {
    [Palette.ink] = { Palette.ink, Palette.slate, Palette.graphite },
    [Palette.slate] = { Palette.slate, Palette.graphite, Palette.graphite },
    [Palette.graphite] = { Palette.graphite, Palette.graphite, Palette.graphite },
    [Palette.blue] = { Palette.blue, Palette.sky, Palette.sky },
    [Palette.sky] = { Palette.sky, Palette.sky, Palette.sky },
    [Palette.red] = { Palette.red, Palette.blush, Palette.blush },
    [Palette.paper] = { Palette.paper, Palette.paper, Palette.paper },
}

-- Set for the length of one S:draw, so the helpers below need not be handed it.
local fade, fadeSeed = 0, 0

local function colour(c)
    local ramp = FADED[c]
    love.graphics.setColor(ramp and ramp[math.min(3, math.floor(fade * 3) + 1)] or c)
end

local function dot(x, y)
    x, y = math.floor(x), math.floor(y)
    if fade == 0 or util.hash01(x, y, fadeSeed) > fade then
        love.graphics.rectangle("fill", x, y, 1, 1)
    end
end

local function rect(x, y, w, h)
    if fade == 0 then
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
        return
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do dot(x + i, y + j) end
    end
end

-- A ring laid clockwise from twelve o'clock as far as `p` has got, two pixels
-- thick -- the boards' hand-drawn ring (`ring` above), through the fade.
local function scribble(cx, cy, r, p, dotted)
    local n = math.floor(2 * math.pi * r * 1.5)
    for k = 0, math.floor(n * util.clamp(p, 0, 1)) - 1 do
        if not dotted or k % 4 == 0 then
            local a = -math.pi / 2 + 2 * math.pi * k / n
            local c, s = math.cos(a), math.sin(a)
            dot(cx + c * r + 0.5, cy + s * r + 0.5)
            if not dotted then dot(cx + c * (r + 1) + 0.5, cy + s * (r + 1) + 0.5) end
        end
    end
end

local HEAD = { ".ooo.", "ooooo", ".ooo." }

function S:drawPad(i)
    local p = self.pads[i]
    local lit, wrong = self.lit[i], self.flash == i
    local u = lit and 1 - lit / LIT or 0 -- 0 to 1 over the note's sounding

    local hx, hy = p.x, p.hy
    if wrong then
        hx = hx + (math.floor(self.flashT * 30) % 2 == 0 and -1 or 1)
    elseif lit then
        hy = hy - math.floor(HOP * math.sin(math.pi * u) + 0.5)
    end
    colour(wrong and Palette.red or Palette.ink)
    for r, row in ipairs(HEAD) do
        for c = 1, #row do
            if row:sub(c, c) == "o" then dot(hx - 3 + c, hy - 2 + r) end
        end
    end
    rect(hx + 2, hy - 7, 1, 7)

    if wrong then
        colour(Palette.red)
        scribble(p.x, p.y, NOTE_R, 1)
    elseif self.circled[i] then
        colour(Palette.blue)
        scribble(p.x, p.y, NOTE_R, self.circled[i])
    elseif self.state ~= "won" then
        -- Where to stand, dotted, the way a board's answers are.
        colour(Palette.graphite)
        scribble(p.x, p.y, NOTE_R, 1, true)
    end
    if lit then
        colour(Palette.blue)
        scribble(p.x, p.y, NOTE_R + 2 + math.floor((RIPPLE - 1) * u), 1, u > 0.5)
    end
end

function S:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / FADE, 0, 1) or 0
    fadeSeed = self.seed

    for i = 1, #self.pads do self:drawPad(i) end

    -- The bell, a pixel to one side on every other beat while it plays: a
    -- swing, at whole pixels and no angle.
    local rows = Sprites.HANDBELL
    local swing = 0
    if self.state == "playing" then
        swing = self.beat % 2 == 0 and -1 or 1
    end
    local b = self.bell
    local bx = math.floor(b.x - #rows[1] / 2) + swing
    local by = math.floor(b.y - #rows / 2)
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)
            if ch ~= "." then
                colour(Palette.key[ch])
                dot(bx + c - 1, by + r - 1)
            end
        end
    end

    -- Tries left, as tally strokes beside the bell; a spent one goes red.
    for k = 1, TRIES do
        colour(k <= TRIES - self.tries and Palette.red or Palette.slate)
        rect(b.x + BELL_RX + 2 + k * 3, b.y - 2, 1, 5)
    end

    fade = 0
end

--- the gym -------------------------------------------------------------------------

-- P.E.'s two sheets, and the only two printed out of the page itself: the
-- calendar's day boxes (`days` on its paper in src/subjects.lua) are the gym
-- floor, so the pit is a block of them and the hopscotch a path of them, and
-- nothing is ruled that the page had not ruled already.
--
-- Both are races against a clock hung under the run's own (src/hud.lua, through
-- Worksheet.clock), both are flagged where they start, and both open and close
-- on the whistle -- the P.E. boss's own (src/sfx.lua), which is the one sound in
-- the book that means a drill has begun or ended. Losing either costs nothing
-- but the prize: the sheet fades off the page the way a failed Simon does.

local DAYS = { w = 32, h = 24, rule = 2 } -- a page with no day boxes of its own
local GYM_FADE = 1.2

-- How far into a box the player's middle must be before it counts as standing
-- in it. Without it the rule between two boxes is a pixel you are in both of,
-- and a hopscotch turned at a corner would clip the box off the path beside it.
local SURE = 3

local function daysOf(game)
    return game.subject.paper and game.subject.paper.days or DAYS
end

-- A flag's rows (src/sprites.lua), its pole's foot at (x, y), through the fade.
local function plant(rows, x, y)
    local top = y - #rows + 1
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)
            if ch ~= "." then
                colour(Palette.key[ch])
                dot(x + c - 1, top + r - 1)
            end
        end
    end
end

-- What a sheet that is under way says when it starts and when it is over, and
-- what every one of those moments sounds like.
-- A start is the notice line's; an end, given where it happened, is shouted
-- there like every sheet's verdict.
local function call(game, text, x, y, colour)
    if x then shout(game, text, x, y, colour) else game:say(text) end
    Sfx.play("whistle")
end

-- The dodgeball pit. A block of day boxes, ruled round heavier than the page,
-- with a flag on its corner. Walk in and the whistle goes: from then on the
-- class is *thrown* at you -- monsters of the minute launched off the ring in a
-- straight line through where you are, at a pace no walker has -- and you have
-- to last the clock without being touched and without stepping out. Any hit,
-- from a thrown one or anything else on the page, is out; so is leaving.
-- Lasting it is a diamond in the middle of the pit.
--
-- Not a wall: nothing stops you walking out, because walking out is the other
-- way to lose, and a pit you could not leave would be the boss's box with a
-- prize in it. The thrown ones fly on past the pit and, once well clear of it
-- (or the moment the drill is over), stop being balls and join the horde --
-- dodgeballs are the class, after all.
local D = {}
D.__index = D

-- In day boxes, and the other way the pit climbs the course: a first-year's is
-- a roomy 5 by 5 to run round in (160 by 120, two thirds of a screen's height),
-- a bachelor's 4 by 4, and from a master's on 4 by 3 -- one screen of floor
-- with room round it, where dodging is stepping aside rather than running.
local PIT = { school = { 5, 5 }, bachelor = { 4, 4 }, masters = { 4, 3 }, phd = { 4, 3 } }
local PIT_TIME = { school = 10, bachelor = 12, masters = 15, phd = 15 }
local THROW_EVERY = { school = 1.4, bachelor = 1.1, masters = 0.9, phd = 0.7 }
local THROW_SPEED = { school = 140, bachelor = 155, masters = 170, phd = 190 }
local THROW_SPREAD = 0.12 -- radians either side of dead on: aimed, not homing
local THROW_FIRST = 0.8   -- the first comes a beat after the whistle, not on it

function D.new(x, y, courseKey, days)
    local pw, ph = unpack(PIT[courseKey] or PIT.school)
    local i0 = math.floor(x / days.w) - math.floor(pw / 2)
    local j0 = math.floor(y / days.h) - math.floor(ph / 2)
    local l, t = i0 * days.w, j0 * days.h
    local r, b = l + pw * days.w, t + ph * days.h
    return setmetatable({
        kind = "dodgeball",
        x = (l + r) / 2, y = (t + b) / 2,
        hw = (r - l) / 2 + 1, hh = (b - t) / 2 + days.rule,
        x0 = l, y0 = t, x1 = r, y1 = b, rule = days.rule,
        time = PIT_TIME[courseKey] or PIT_TIME.school,
        every = THROW_EVERY[courseKey] or THROW_EVERY.school,
        speed = THROW_SPEED[courseKey] or THROW_SPEED.school,
        thrown = {},
        state = "open",
        seed = util.hash01(x, y, 5) * 1000,
    }, D)
end

-- Inside the border, not on it: the border is the line you step over.
function D:inside(px, py)
    return px > self.x0 + 2 and px < self.x1 - 2
        and py > self.y0 + self.rule + 2 and py < self.y1 - 2
end

function D:throw(game)
    local p, spawner = game.player, game.spawner
    local a = love.math.random() * math.pi * 2
    local reach = spawner:ring(game)
    local sx, sy = p.x + math.cos(a) * reach, p.y + math.sin(a) * reach
    local e = game:spawnEnemy(spawner:pick(game.time), sx, sy)
    local aim = math.atan2(p.y - sy, p.x - sx)
        + (love.math.random() * 2 - 1) * THROW_SPREAD
    -- The bowl's own steering (Enemy:update): down a locked line at a locked
    -- speed, stopped by a pen line like anything else -- which is the one
    -- thing you can do about a throw besides stepping out of its way.
    e.drive = { dash = true, dx = math.cos(aim), dy = math.sin(aim), speed = self.speed }
    self.thrown[#self.thrown + 1] = { e = e, x = sx, y = sy, far = reach * 2 }
end

-- Thrown ones that have flown their course, or all of them when the drill is
-- over, go back to walking: what was a ball is a monster again.
function D:land(all)
    for k = #self.thrown, 1, -1 do
        local t = self.thrown[k]
        if t.e.gone or all or util.len(t.e.x - t.x, t.e.y - t.y) > t.far then
            if t.e.drive and t.e.drive.dash then t.e.drive = nil end
            table.remove(self.thrown, k)
        end
    end
end

function D:finish(game, won)
    self.live = false
    self:land(true)
    if won then
        self.state = "won"
        award(game, "diamond", self.x, self.y)
        call(game, "SAFE!", self.x, self.y0 - 2, Palette.blue)
    else
        self.state = "fading"
        self.t = 0
        call(game, "OUT!", game.player.x, game.player.y - 14, Palette.red)
    end
end

function D:update(dt, game)
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= GYM_FADE then self.state = "gone" end
        return
    end
    if self.state ~= "open" and not self.live then return end

    local p = game.player
    local inside = self:inside(p.x, p.y)
    if not self.live then
        if inside then
            self.live = true
            self.left = self.time
            self.throwT = THROW_FIRST
            self.hits = p.hits
            call(game, "DODGE!")
        end
        return
    end

    if not inside or p.hits > self.hits then
        self:finish(game, false)
        return
    end
    self:land(false)
    self.left = self.left - dt
    if self.left <= 0 then
        self:finish(game, true)
        return
    end
    self.throwT = self.throwT - dt
    if self.throwT <= 0 then
        self.throwT = self.throwT + self.every
        self:throw(game)
    end
end

function D:clock()
    return self.live and self.left
end

function D:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / GYM_FADE, 0, 1) or 0
    fadeSeed = self.seed

    -- Heavier than the page's own ruling, so the pit reads as painted on the
    -- gym floor rather than as more days: two pixels all round, in slate
    -- until the whistle and red while you are in it. Just inside the ruling
    -- rather than over it, because red printed over the sky rules overprints
    -- to slate (src/overprint.lua) and the pit going live would go live on two
    -- of its four sides.
    colour(self.live and Palette.red or Palette.slate)
    local l, t = self.x0 + 1, self.y0 + self.rule
    local w, h = self.x1 - l, self.y1 - t
    rect(l, t, w, 2)
    rect(l, self.y1 - 2, w, 2)
    rect(l, t, 2, h)
    rect(self.x1 - 2, t, 2, h)

    if self.state == "open" then plant(Sprites.FLAG, self.x0 - 1, self.y0 - 1) end
    fade = 0
end

-- Hopscotch. A path of day boxes, numbered from 1, a flag in the first and the
-- chequered flag in the last. Step into box 1 and the whistle goes; then every
-- box you step into must be the next one along. Stepping into a box off the
-- path, back into one you have been in, or past one, is out, and so is the
-- clock running down. The last box is a heart.
--
-- The path is a walk of boxes that never touches itself -- no box on it sits
-- beside any other but the ones before and after it -- so the way on is always
-- the one numbered box beside you, and a corner turned is never a corner cut
-- through a box that also belongs to the path.
local H = {}
H.__index = H

local HOP_BOXES = { school = 12, bachelor = 16, masters = 20, phd = 24 }
-- Seconds a box, on top of HOP_GRACE. A box is half a second's walk across at
-- the bare speed, so the slack is for the horde standing on the path.
local HOP_PER = { school = 1.5, bachelor = 1.3, masters = 1.15, phd = 1.0 }
local HOP_GRACE = 2
local HOP_SPAN_X, HOP_SPAN_Y = 5, 3 -- how far from the first box it may wander

local function boxKey(i, j) return i * 65536 + j end

-- A walk of `n` boxes from (0, 0), redealt until it fits in the span without
-- touching itself.
local function hopPath(n)
    local steps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for _ = 1, 500 do
        local path, on = { { 0, 0 } }, { [boxKey(0, 0)] = 1 }
        while #path < n do
            local last = path[#path]
            local can = {}
            for _, s in ipairs(steps) do
                local i, j = last[1] + s[1], last[2] + s[2]
                local ok = math.abs(i) <= HOP_SPAN_X and math.abs(j) <= HOP_SPAN_Y
                    and not on[boxKey(i, j)]
                if ok then
                    for _, t in ipairs(steps) do
                        local k = on[boxKey(i + t[1], j + t[2])]
                        if k and k ~= #path then ok = false; break end
                    end
                end
                if ok then can[#can + 1] = { i, j } end
            end
            if #can == 0 then break end
            local c = can[love.math.random(#can)]
            path[#path + 1] = c
            on[boxKey(c[1], c[2])] = #path
        end
        if #path == n then return path end
    end
end

function H.new(x, y, courseKey, days)
    local n = HOP_BOXES[courseKey] or HOP_BOXES.school
    local walk = hopPath(n)
    if not walk then return end
    local bi, bj = math.floor(x / days.w), math.floor(y / days.h)
    local path, index = {}, {}
    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
    for k, c in ipairs(walk) do
        local i, j = bi + c[1], bj + c[2]
        path[k] = { i = i, j = j, x = i * days.w, y = j * days.h }
        index[boxKey(i, j)] = k
        l, t = math.min(l, path[k].x), math.min(t, path[k].y)
        r, b = math.max(r, path[k].x + days.w), math.max(b, path[k].y + days.h)
    end
    return setmetatable({
        kind = "hopscotch",
        x = (l + r) / 2, y = (t + b) / 2, hw = (r - l) / 2, hh = (b - t) / 2,
        days = days, path = path, index = index,
        time = HOP_GRACE + n * (HOP_PER[courseKey] or HOP_PER.school),
        reached = 0,
        state = "open",
        seed = util.hash01(x, y, 6) * 1000,
    }, H)
end

function H:covers(x, y, pad)
    local d = self.days
    for _, c in ipairs(self.path) do
        if x > c.x - pad and x < c.x + d.w + pad
            and y > c.y - pad and y < c.y + d.h + pad then
            return true
        end
    end
    return false
end

function H:finish(game, won)
    self.live = false
    if won then
        self.state = "won"
        local c = self.path[#self.path]
        local hx, hy = c.x + self.days.w / 2, c.y + self.days.h / 2
        award(game, "heart", hx, hy)
        call(game, "FINISH!", hx, hy - 10, Palette.blue)
    else
        self.state = "fading"
        self.t = 0
        call(game, "OUT!", game.player.x, game.player.y - 14, Palette.red)
    end
end

-- Arriving in box `k` of the path, or in a box off it (`k` nil).
function H:step(k, game)
    if not self.live then
        if k == 1 then
            self.live = true
            self.reached = 1
            self.left = self.time
            call(game, "HOP!")
        end
        return
    end
    if k == self.reached + 1 then
        self.reached = k
        if k == #self.path then
            self:finish(game, true)
        else
            Sfx.play("tick")
        end
    else
        self:finish(game, false)
    end
end

function H:update(dt, game)
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= GYM_FADE then self.state = "gone" end
        return
    end
    if self.state ~= "open" then return end

    -- The box under you changes only once you are well into the new one.
    local d, p = self.days, game.player
    local ix, iy = p.x % d.w, p.y % d.h
    if ix >= SURE and ix <= d.w - SURE and iy >= d.rule + SURE and iy <= d.h - SURE then
        local key = boxKey(math.floor(p.x / d.w), math.floor(p.y / d.h))
        if key ~= self.at then
            self.at = key
            self:step(self.index[key], game)
        end
    end

    if self.live then
        self.left = self.left - dt
        if self.left <= 0 then self:finish(game, false) end
    end
end

function H:clock()
    return self.live and self.left
end

function H:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / GYM_FADE, 0, 1) or 0
    fadeSeed = self.seed

    -- Each box chalked round a pixel inside the page's own ruling, with its
    -- number in the middle: slate ahead of you, blue once hopped.
    local d = self.days
    for k, c in ipairs(self.path) do
        local x, y = c.x + 2, c.y + d.rule + 1
        local w, h = d.w - 3, d.h - d.rule - 2
        colour(k <= self.reached and Palette.blue or Palette.slate)
        rect(x, y, w, 1)
        rect(x, y + h - 1, w, 1)
        rect(x, y, 1, h)
        rect(x + w - 1, y, 1, h)
        -- A flagged box's number stands a little right, off its flag.
        local flagged = k == 1 or k == #self.path
        if fade < 0.5 then
            Font.printCentered(tostring(k), c.x + d.w / 2 + (flagged and 4 or 1),
                math.floor(c.y + (d.h + d.rule - Font.height) / 2))
        end
    end

    local first, last = self.path[1], self.path[#self.path]
    plant(Sprites.FLAG, first.x + 4, first.y + d.h - 3)
    plant(Sprites.CHEQUERED, last.x + 4, last.y + d.h - 3)
    fade = 0
end

--- the circuit ---------------------------------------------------------------------

-- SCIENCE's second sheet, and the first answered by drawing a *line* rather
-- than scribbling a cell or standing on a place: a circuit printed on the page
-- with gaps in its wire, a battery, a bulb or two and one bulb ringed in red.
-- Draw a wire across a gap and the circuit is worked out the way a physics
-- book would -- currents through the bulbs, a diode that only lets current one
-- way -- and the ringed bulbs have to come on, fully, with nothing else lit.
--
-- What makes it a puzzle rather than a scribble is that **every printed wire
-- is bare**. The wire you draw joins every piece of copper it touches on its
-- way, so a line dragged carelessly across the board joins the wrong things:
--
-- - **Short circuit.** Your wire joins the battery's two sides with nothing in
--   between (the return wire runs a stub up into the board for exactly this).
--   The battery sparks, it costs the sequence's twenty, and the sheet fades.
-- - **Wrong bulb.** Any bulb without the ring comes on, even dimly: it pops
--   and the sheet fades.
-- - **Rubbed out.** A wire that closes the circuit has to stay whole for a
--   moment while the bulb warms up, and a monster walking over it rubs it out.
--   A drawn wire that did nothing also wears off after a few seconds, which is
--   the way to take back a try that was harmless but wrong.
--
-- It climbs the course by what has to be understood rather than by speed: one
-- gap at a first-year's, two bulbs and the right one to pick at a bachelor's,
-- a diode that has to be wired the right way round at a master's, and two
-- bulbs that must both be fully lit -- in parallel, since in series they share
-- the battery and only glow -- at a doctorate. Right is a wall clock.
local C = {}
C.__index = C

local CU = 8              -- one step of the board's grid, in page pixels
local TOUCH = 2.5         -- how near the pen must come to copper to join it
local TERMINAL = 4        -- a wire end's open circle, a little more forgiving
local BULB_R = 5
local FULL = 0.9          -- of a bulb across the whole battery: lit
local GLOW = 0.1          -- and above this it is on, if only dimly
local SETTLE = 0.8        -- seconds a closed circuit must stay whole to count
local WIRE_LIFE = 6       -- seconds a drawn wire that did nothing lasts
local CIRCUIT_FADE = 1.2

-- The boards, in grid steps. `wires` are polylines of one net each (the first
-- entry the net); `parts` sit between two grid points (`bulb` and `diode`, a
-- diode's first end its anode); `ends` are the open circles where a gap is.
-- The battery always sits between (0, 3), its + side, and (0, 5). `ring`
-- lists the bulbs that must light, or `pick` says one of them is rolled.
-- Every board is dealt mirrored either way at random, so the layouts are
-- learnable as circuits and not as pictures.
local BOARDS_C = {
    school = {
        { -- the gap in the top wire, and the return wire's stub reaching up
            w = 12, h = 8,
            wires = { { "p", 0, 3, 0, 0, 5, 0 }, { "a", 8, 0, 12, 0, 12, 3 },
                      { "n", 12, 5, 12, 8, 0, 8, 0, 5 }, { "n", 6, 8, 6, 3 } },
            parts = { { "bulb", 12, 3, 12, 5, "a", "n" } },
            ends = { { 5, 0 }, { 8, 0 }, { 6, 3 } },
            ring = { 1 },
        },
        { -- the gap down the far side, the stub reaching across the middle
            w = 12, h = 8,
            wires = { { "p", 0, 3, 0, 0, 12, 0, 12, 2 }, { "a", 12, 5, 12, 8, 7, 8 },
                      { "n", 5, 8, 0, 8, 0, 5 }, { "n", 3, 8, 3, 4, 8, 4 } },
            parts = { { "bulb", 7, 8, 5, 8, "a", "n" } },
            ends = { { 12, 2 }, { 12, 5 }, { 8, 4 } },
            ring = { 1 },
        },
    },
    bachelor = {
        { -- one wire end, two bulbs it could feed
            w = 12, h = 8,
            wires = { { "p", 0, 3, 0, 0, 4, 0 }, { "a", 7, 0, 12, 0, 12, 2 },
                      { "b", 4, 3, 7, 3, 7, 4 }, { "n", 12, 4, 12, 8 },
                      { "n", 7, 6, 7, 8 }, { "n", 12, 8, 0, 8, 0, 5 } },
            parts = { { "bulb", 12, 2, 12, 4, "a", "n" }, { "bulb", 7, 4, 7, 6, "b", "n" } },
            ends = { { 4, 0 }, { 7, 0 }, { 4, 3 } },
            pick = true,
        },
        { -- the same choice with the return wire's stub between the two
            w = 12, h = 8,
            wires = { { "p", 0, 3, 0, 0, 5, 0 }, { "a", 8, 0, 12, 0, 12, 2 },
                      { "b", 5, 3, 5, 4 }, { "n", 12, 4, 12, 8 },
                      { "n", 5, 6, 5, 8 }, { "n", 12, 8, 0, 8, 0, 5 },
                      { "n", 9, 8, 9, 4 } },
            parts = { { "bulb", 12, 2, 12, 4, "a", "n" }, { "bulb", 5, 4, 5, 6, "b", "n" } },
            ends = { { 5, 0 }, { 8, 0 }, { 5, 3 }, { 9, 4 } },
            pick = true,
        },
    },
    masters = {
        { -- two ways to the bulb, each through a diode; one of them is backwards
            w = 12, h = 9,
            wires = { { "p", 0, 3, 0, 0, 3, 0 }, { "a", 6, 0, 8, 0 },
                      { "c", 10, 0, 12, 0, 12, 5 }, { "b", 3, 3, 3, 4, 6, 4 },
                      { "c", 8, 4, 12, 4 }, { "n", 12, 7, 12, 9, 0, 9, 0, 5 },
                      { "n", 6, 9, 6, 7 } },
            parts = { { "diode", 8, 0, 10, 0, "a", "c" }, { "diode", 6, 4, 8, 4, "b", "c" },
                      { "bulb", 12, 5, 12, 7, "c", "n" } },
            ends = { { 3, 0 }, { 6, 0 }, { 3, 3 }, { 6, 7 } },
            ring = { 3 },
            flip = { 1, 2 }, -- one of these diodes is dealt backwards
        },
    },
    phd = {
        -- Two bulbs to be lit fully, and the obvious two wires put them one
        -- after the other, where they share the battery and only glow. Side by
        -- side takes three: each bulb's near end to +, and the first's far end
        -- to the return wire.
        {
            w = 12, h = 10,
            wires = { { "p", 0, 3, 0, 0, 3, 0 }, { "p", 3, 0, 3, 3, 9, 3 },
                      { "a", 6, 0, 7, 0 }, { "m", 9, 0, 10, 0 },
                      { "d", 12, 1, 12, 3 }, { "n", 12, 5, 12, 10, 0, 10, 0, 5 },
                      { "n", 11, 10, 11, 7 } },
            parts = { { "bulb", 7, 0, 9, 0, "a", "m" }, { "bulb", 12, 3, 12, 5, "d", "n" } },
            ends = { { 3, 0 }, { 6, 0 }, { 10, 0 }, { 12, 1 }, { 9, 3 }, { 11, 7 } },
            ring = { 1, 2 },
        },
    },
}
-- And a master's board now and then, the way every book's doctorate asks.
BOARDS_C.phd[2] = BOARDS_C.masters[1]
-- The page point of a grid point, mirrored as dealt.
function C:at(gx, gy)
    if self.mx then gx = self.gw - gx end
    if self.my then gy = self.gh - gy end
    return self.x0 + gx * CU, self.y0 + gy * CU
end

function C.new(x, y, courseKey)
    local list = BOARDS_C[courseKey] or BOARDS_C.school
    local b = list[love.math.random(#list)]
    local c = setmetatable({
        kind = "circuit",
        x = x, y = y,
        gw = b.w, gh = b.h,
        x0 = math.floor(x - b.w * CU / 2), y0 = math.floor(y - b.h * CU / 2),
        mx = love.math.random() < 0.5, my = love.math.random() < 0.5,
        hw = b.w * CU / 2 + BULB_R + 7, hh = b.h * CU / 2 + BULB_R + 7,
        segs = {}, parts = {}, ends = {},
        wires = {},
        state = "open",
        seed = util.hash01(x, y, 7) * 1000,
    }, C)

    for _, w in ipairs(b.wires) do
        for k = 2, #w - 3, 2 do
            local ax, ay = c:at(w[k], w[k + 1])
            local bx, by = c:at(w[k + 2], w[k + 3])
            c.segs[#c.segs + 1] = { net = w[1], ax = ax, ay = ay, bx = bx, by = by }
        end
    end
    local flipped = b.flip and b.flip[love.math.random(#b.flip)]
    for i, p in ipairs(b.parts) do
        local ax, ay = c:at(p[2], p[3])
        local bx, by = c:at(p[4], p[5])
        local na, nb = p[6], p[7]
        local part = { kind = p[1], ax = ax, ay = ay, bx = bx, by = by,
            x = (ax + bx) / 2, y = (ay + by) / 2, a = na, b = nb, lit = 0 }
        -- A diode dealt backwards points the other way along the same wire,
        -- which is all the drawing has to say and all the solver reads.
        if i == flipped then
            part.ax, part.ay, part.bx, part.by = bx, by, ax, ay
            part.a, part.b = nb, na
        end
        c.parts[i] = part
    end
    for _, e in ipairs(b.ends) do
        local ex, ey = c:at(e[1], e[2])
        c.ends[#c.ends + 1] = { x = ex, y = ey, nets = {} }
    end
    local bx, by = c:at(0, 3)
    local nx, ny = c:at(0, 5)
    c.battery = { px = bx, py = by, nx = nx, ny = ny, x = (bx + nx) / 2, y = (by + ny) / 2 }
    -- Which copper each wire end is the end of, so a solved wire can be ruled
    -- to it (C:attach).
    for _, e in ipairs(c.ends) do
        for _, sg in ipairs(c.segs) do
            if util.distToSegment(e.x, e.y, sg.ax, sg.ay, sg.bx, sg.by) <= TOUCH then
                e.nets[sg.net] = true
            end
        end
    end

    c.ring = {}
    if b.pick then
        local bulbs = {}
        for i, p in ipairs(c.parts) do
            if p.kind == "bulb" then bulbs[#bulbs + 1] = i end
        end
        c.ring[bulbs[love.math.random(#bulbs)]] = true
    else
        for _, i in ipairs(b.ring) do c.ring[i] = true end
    end
    return c
end

-- Every net a page point touches: copper within TOUCH, a wire end's circle,
-- the battery's body (both sides: drawing over it is the shortest short) and a
-- part's body (both its ends: drawn over, it is bypassed).
function C:netsAt(px, py, into)
    for _, s in ipairs(self.segs) do
        if util.distToSegment(px, py, s.ax, s.ay, s.bx, s.by) <= TOUCH then
            into[s.net] = true
        end
    end
    for _, p in ipairs(self.parts) do
        local r = p.kind == "bulb" and BULB_R + 1 or 4
        if util.len(px - p.x, py - p.y) <= r then
            into[p.a], into[p.b] = true, true
        end
    end
    local bt = self.battery
    if math.abs(px - bt.x) <= 5 and math.abs(py - bt.y) <= 5 then
        into.p, into.n = true, true
    end
end

-- Solve the circuit as it stands: union the nets every drawn wire joins, then
-- put the battery's + at 1 and its - at 0 and find every other node's voltage
-- (each bulb a resistance of 1, a forward diode a very small one, a reversed
-- diode none at all) by Gaussian elimination -- the board has at most half a
-- dozen nodes. A node joined to nothing gets a whisper of a path to 0 so the
-- matrix is never singular, and since a bulb's brightness is read off its
-- current that whisper never lights one. Returns "short", or each part's
-- current in `lit`.
local function find(root, n)
    while root[n] ~= n do n = root[n] end
    return n
end

function C:solve()
    local root = { p = "p", n = "n" }
    local function add(n) if not root[n] then root[n] = n end end
    for _, p in ipairs(self.parts) do add(p.a); add(p.b) end
    for _, w in ipairs(self.wires) do
        local first
        for n in pairs(w.nets) do
            add(n)
            if first then root[find(root, n)] = find(root, first) else first = n end
        end
    end
    local P, N = find(root, "p"), find(root, "n")
    if P == N then return "short" end

    -- The unknowns: every node that is neither side of the battery.
    local index, nodes = {}, {}
    for n in pairs(root) do
        local r = find(root, n)
        if r ~= P and r ~= N and not index[r] then
            nodes[#nodes + 1] = r
            index[r] = #nodes
        end
    end
    table.sort(nodes)
    for i, r in ipairs(nodes) do index[r] = i end

    local on = {}
    for i, p in ipairs(self.parts) do on[i] = true end
    local volts
    for _ = 1, 4 do
        local m = #nodes
        local A, B = {}, {}
        for i = 1, m do
            A[i] = {}
            for j = 1, m do A[i][j] = 0 end
            A[i][i] = 1e-6
            B[i] = 0
        end
        local function v(r) return r == P and 1 or r == N and 0 or nil end
        for i, p in ipairs(self.parts) do
            local g = p.kind == "bulb" and 1 or (on[i] and 100 or 0)
            local ra, rb = find(root, p.a), find(root, p.b)
            if g > 0 and ra ~= rb then
                local ia, ib = index[ra], index[rb]
                if ia then A[ia][ia] = A[ia][ia] + g end
                if ib then A[ib][ib] = A[ib][ib] + g end
                if ia and ib then
                    A[ia][ib] = A[ia][ib] - g
                    A[ib][ia] = A[ib][ia] - g
                end
                if ia and not ib then B[ia] = B[ia] + g * v(rb) end
                if ib and not ia then B[ib] = B[ib] + g * v(ra) end
            end
        end
        -- Elimination with partial pivoting; m is tiny.
        for col = 1, m do
            local best = col
            for r = col + 1, m do
                if math.abs(A[r][col]) > math.abs(A[best][col]) then best = r end
            end
            A[col], A[best] = A[best], A[col]
            B[col], B[best] = B[best], B[col]
            for r = col + 1, m do
                local f = A[r][col] / A[col][col]
                if f ~= 0 then
                    for k = col, m do A[r][k] = A[r][k] - f * A[col][k] end
                    B[r] = B[r] - f * B[col]
                end
            end
        end
        local x = {}
        for r = m, 1, -1 do
            local s = B[r]
            for k = r + 1, m do s = s - A[r][k] * x[k] end
            x[r] = s / A[r][r]
        end
        volts = function(r) return v(r) or x[index[r]] end

        -- A diode conducting backwards is switched off and one that is off but
        -- pushed forwards is switched on, and the board solved again.
        local changed = false
        for i, p in ipairs(self.parts) do
            if p.kind == "diode" then
                local d = volts(find(root, p.a)) - volts(find(root, p.b))
                local want = d > 1e-4
                if want ~= on[i] then on[i] = want; changed = true end
            end
        end
        if not changed then break end
    end

    local lit = {}
    for i, p in ipairs(self.parts) do
        lit[i] = p.kind == "bulb"
            and math.abs(volts(find(root, p.a)) - volts(find(root, p.b))) or 0
    end
    return lit
end

-- What the board says now, and what follows from it.
function C:judge(game)
    local lit = self:solve()
    if lit == "short" then
        self.state, self.t = "fading", 0
        self.sparks = 0.6
        local bt = self.battery
        game.particles:burst(bt.x, bt.y, 14, Palette.red)
        game.particles:burst(bt.x, bt.y, 6, Palette.ink)
        sting(game)
        shout(game, "SHORT CIRCUIT!", bt.x + (self.mx and -20 or 20), bt.y - 10, Palette.red)
        Sfx.play("stamp")
        return
    end
    local all = true
    for i, p in ipairs(self.parts) do
        p.lit = lit[i]
        if p.kind == "bulb" then
            if self.ring[i] then
                if lit[i] < FULL then all = false end
            elseif lit[i] > GLOW then
                self.state, self.t = "fading", 0
                self.popped = i
                game.particles:burst(p.x, p.y, 10, Palette.red)
                shout(game, "WRONG BULB!", p.x, p.y - BULB_R - 6, Palette.red)
                Sfx.play("stamp")
                return
            end
        end
    end
    if all and self.state == "open" then
        self.state, self.t = "closing", 0
        Sfx.play("tick")
    elseif not all and self.state == "closing" then
        self.state = "open"
    end
end

-- The pen's wire as it is drawn: points a pixel apart, and every net touched.
-- Where on the board a wire that reached `net` at (px, py) is fastened: the
-- middle of that net's wire end if it was reached there, else the nearest
-- point of that net's copper (every printed wire is level or upright, so the
-- nearest point is a clamp), else -- a part's body, the battery's -- the point
-- itself. What the solved board rules its straight wires between.
function C:attach(net, px, py)
    for _, e in ipairs(self.ends) do
        if e.nets[net] and util.len(px - e.x, py - e.y) <= TERMINAL + TOUCH then
            return e.x, e.y
        end
    end
    local best, bx, by = TOUCH + 1
    for _, sg in ipairs(self.segs) do
        if sg.net == net then
            local qx = util.clamp(px, math.min(sg.ax, sg.bx), math.max(sg.ax, sg.bx))
            local qy = util.clamp(py, math.min(sg.ay, sg.by), math.max(sg.ay, sg.by))
            local d = util.len(px - qx, py - qy)
            if d < best then best, bx, by = d, qx, qy end
        end
    end
    if bx then return bx, by end
    return px, py
end

function C:trace(px, py)
    local w = self.drawing
    local fx, fy = math.floor(px), math.floor(py)
    local last = w.pts[#w.pts]
    if not last or last.x ~= fx or last.y ~= fy then
        w.pts[#w.pts + 1] = { x = fx, y = fy }
    end
    local had = {}
    for n in pairs(w.nets) do had[n] = true end
    self:netsAt(px, py, w.nets)
    for _, e in ipairs(self.ends) do
        if util.len(px - e.x, py - e.y) <= TERMINAL then
            -- A wire end joins whatever its copper does; the circle only
            -- widens the target.
            self:netsAt(e.x, e.y, w.nets)
        end
    end
    -- Each net newly reached, in the order the pen reached it, and where.
    local changed = false
    for n in pairs(w.nets) do
        if not had[n] then
            changed = true
            local ax, ay = self:attach(n, px, py)
            ax, ay = math.floor(ax), math.floor(ay)
            local j = w.joins[#w.joins]
            if not j or j.x ~= ax or j.y ~= ay then
                w.joins[#w.joins + 1] = { x = ax, y = ay }
            end
        end
    end
    return changed
end

-- A wire is rubbed out by anything walking over it.
function C:trodden(w, game)
    local hit = false
    game:eachWithin(self.x, self.y, math.max(self.hw, self.hh) + 6, function(e)
        local r = (e.radius or 4) + 1
        for k = 1, #w.pts, 2 do
            local q = w.pts[k]
            if math.abs(q.x - e.x) <= r and math.abs(q.y - e.y) <= r then
                hit = true
                return true
            end
        end
    end)
    return hit
end

function C:update(dt, game, pen)
    if self.sparks then self.sparks = math.max(0, self.sparks - dt) end
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= CIRCUIT_FADE then self.state = "gone" end
        return
    end
    if self.state == "won" then return end

    local changed = false

    -- The pen on the board draws a wire; off it, or lifted, the wire is done.
    local onBoard = pen and math.abs(pen.x - self.x) <= self.hw
        and math.abs(pen.y - self.y) <= self.hh
    if onBoard then
        if not self.drawing then
            self.drawing = { pts = {}, nets = {}, joins = {}, age = 0 }
            self.wires[#self.wires + 1] = self.drawing
            self.penX, self.penY = nil, nil
        end
        local x0, y0 = self.penX or pen.x, self.penY or pen.y
        local dx, dy = pen.x - x0, pen.y - y0
        local steps = math.max(1, math.ceil(util.len(dx, dy)))
        for s = 0, steps do
            if self:trace(x0 + dx * s / steps, y0 + dy * s / steps) then
                changed = true
            end
        end
        self.penX, self.penY = pen.x, pen.y
    elseif self.drawing then
        self.drawing = nil
        self.penX, self.penY = nil, nil
    end

    -- Wires wear off, and are rubbed out by feet. The one being drawn is held.
    for k = #self.wires, 1, -1 do
        local w = self.wires[k]
        if w ~= self.drawing then
            w.age = w.age + dt
            local closing = self.state == "closing"
            if (not closing and w.age >= WIRE_LIFE) or self:trodden(w, game) then
                if w.age < WIRE_LIFE then
                    local q = w.pts[math.ceil(#w.pts / 2)]
                    if q then game.particles:burst(q.x, q.y, 4, Palette.blue) end
                end
                table.remove(self.wires, k)
                changed = true
            end
        end
    end

    if changed then self:judge(game) end
    if self.state == "fading" then return end

    if self.state == "closing" then
        self.t = self.t + dt
        if self.t >= SETTLE then
            self.state = "won"
            -- What closed it stays on the board, and stays as a wire would be
            -- drawn on a circuit diagram: ruled straight from copper to
            -- copper rather than as the scribble that made it. A wire that
            -- joined nothing to anything goes.
            self.drawing = nil
            for k = #self.wires, 1, -1 do
                local w = self.wires[k]
                if #w.joins >= 2 then w.straight = w.joins else table.remove(self.wires, k) end
            end
            -- The wall clock under the board, where taking it is a step away.
            local cx, cy = self.x, self.y + self.hh + 6
            game.pickups[#game.pickups + 1] = Pickup.new("clock", cx, cy)
            game.particles:burst(cx, cy, 10, Palette.slate)
            shout(game, "LIGHTS ON!", self.x, self.y - self.hh, Palette.blue)
            Sfx.play("accept")
        end
    end
end

-- The board's symbols, a pixel at a time through the fade helpers (`rect`,
-- `dot`), so a lost board fades the way Simon's does.
local function hline(x0, x1, y)
    if x1 < x0 then x0, x1 = x1, x0 end
    rect(x0, y, x1 - x0 + 1, 1)
end

local function vline(x, y0, y1)
    if y1 < y0 then y0, y1 = y1, y0 end
    rect(x, y0, 1, y1 - y0 + 1)
end

local function circle(cx, cy, r, step)
    local n = math.floor(2 * math.pi * r * 1.5)
    for k = 0, n - 1, step or 1 do
        local a = 2 * math.pi * k / n
        dot(cx + math.cos(a) * r + 0.5, cy + math.sin(a) * r + 0.5)
    end
end

function C:drawBulb(i, p)
    local cx, cy = math.floor(p.x), math.floor(p.y)
    local vertical = p.ax == p.bx
    -- The leads, from the grid points to the glass.
    colour(Palette.ink)
    if vertical then
        vline(cx, math.min(p.ay, p.by), cy - BULB_R)
        vline(cx, cy + BULB_R, math.max(p.ay, p.by))
    else
        hline(math.min(p.ax, p.bx), cx - BULB_R, cy)
        hline(cx + BULB_R, math.max(p.ax, p.bx), cy)
    end

    local popped = self.popped == i
    local on = not popped and p.lit or 0
    if on > GLOW then
        -- Lit: the glass filled, and at full brightness rays round it.
        colour(Palette.blush)
        for yy = -BULB_R + 1, BULB_R - 1 do
            for xx = -BULB_R + 1, BULB_R - 1 do
                if xx * xx + yy * yy < (BULB_R - 0.5) ^ 2
                    and (on >= FULL or (xx + yy) % 2 == 0) then
                    dot(cx + xx, cy + yy)
                end
            end
        end
        if on >= FULL then
            colour(Palette.red)
            for k = 0, 7 do
                local a = k * math.pi / 4 + math.pi / 8
                local c, s = math.cos(a), math.sin(a)
                dot(cx + c * (BULB_R + 2) + 0.5, cy + s * (BULB_R + 2) + 0.5)
                dot(cx + c * (BULB_R + 3) + 0.5, cy + s * (BULB_R + 3) + 0.5)
            end
        end
    end
    colour(popped and Palette.red or Palette.ink)
    circle(cx, cy, BULB_R)
    -- The filament's cross.
    for k = -2, 2 do
        if not popped or k % 2 == 0 then
            dot(cx + k, cy + k)
            dot(cx + k, cy - k)
        end
    end
    if self.ring[i] and self.state ~= "won" then
        colour(Palette.red)
        circle(cx, cy, BULB_R + 5, 3)
    end
end

-- A diode: a triangle pointing the way current may go, and the bar it meets.
function C:drawDiode(p)
    local cx, cy = math.floor(p.x), math.floor(p.y)
    local ux, uy = util.normalize(p.bx - p.ax, p.by - p.ay)
    colour(Palette.ink)
    -- Leads, anode side to the triangle's base and the bar to the cathode side.
    if uy == 0 then
        hline(math.floor(p.ax), cx - 3 * ux, cy)
        hline(cx + 3 * ux, math.floor(p.bx), cy)
    else
        vline(cx, math.floor(p.ay), cy - 3 * uy)
        vline(cx, cy + 3 * uy, math.floor(p.by))
    end
    for k = 0, 5 do
        local h = 3 - math.floor(k / 2)
        for s = -h, h do
            local along = -3 + k
            if uy == 0 then dot(cx + along * ux, cy + s) else dot(cx + s, cy + along * uy) end
        end
    end
    for s = -3, 3 do
        if uy == 0 then dot(cx + 3 * ux, cy + s) else dot(cx + s, cy + 3 * uy) end
    end
end

function C:drawBattery()
    local bt = self.battery
    local cx = math.floor(bt.x)
    local dir = bt.ny > bt.py and 1 or -1
    local cy = math.floor(bt.y)
    colour(Palette.ink)
    vline(cx, math.floor(bt.py), cy - 2 * dir)
    vline(cx, cy + 2 * dir, math.floor(bt.ny))
    -- The long plate on the + side, the short thick one on the -.
    rect(cx - 4, cy - 2 * dir, 9, 1)
    rect(cx - 2, cy + 1 * dir, 5, 2)
    colour(Palette.red)
    local sx = cx + (self.mx and -9 or 6)
    rect(sx, cy - 5 * dir - 1, 3, 1)
    rect(sx + 1, cy - 5 * dir - 2, 1, 3)
    if self.sparks and self.sparks > 0 then
        for k = 1, 6 do
            local a = util.hash01(k, math.floor(self.sparks * 20), self.seed) * math.pi * 2
            dot(cx + math.cos(a) * 7, cy + math.sin(a) * 7)
        end
    end
end

function C:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / CIRCUIT_FADE, 0, 1) or 0
    fadeSeed = self.seed

    colour(Palette.ink)
    for _, s in ipairs(self.segs) do
        if s.ay == s.by then hline(s.ax, s.bx, s.ay) else vline(s.ax, s.ay, s.by) end
    end
    for _, e in ipairs(self.ends) do
        colour(Palette.paper)
        rect(e.x - 1, e.y - 1, 3, 3)
        colour(Palette.ink)
        circle(e.x, e.y, 2)
    end
    self:drawBattery()
    for i, p in ipairs(self.parts) do
        if p.kind == "bulb" then self:drawBulb(i, p) else self:drawDiode(p) end
    end

    -- The wires you drew, in the pen's blue, going pale as they wear off --
    -- and once the board is solved, ruled straight between what they joined.
    for _, w in ipairs(self.wires) do
        local left = WIRE_LIFE - w.age
        colour((self.state == "closing" or self.state == "won") and Palette.blue
            or left > 1.5 and Palette.blue or Palette.sky)
        if w.straight then
            for k = 1, #w.straight - 1 do
                local a, b = w.straight[k], w.straight[k + 1]
                local n = math.max(math.abs(b.x - a.x), math.abs(b.y - a.y), 1)
                for t = 0, n do
                    dot(a.x + (b.x - a.x) * t / n + 0.5, a.y + (b.y - a.y) * t / n + 0.5)
                end
            end
        else
            for _, q in ipairs(w.pts) do dot(q.x, q.y) end
        end
    end
    fade = 0
end

--- join the dots -------------------------------------------------------------------

-- ART's first sheet: numbered dots that make a picture once they are joined in
-- order. Touch them with the pen one after another -- a line drawn through
-- them, or a tap on each, whichever the horde leaves room for -- and the sheet
-- rules the line in behind you. Touch one out of order and every line comes
-- off and you start again from the first; the third time, the dots wander off
-- the page. Finished, the outline is closed and the picture pays a gold star.
--
-- It climbs by count -- six or seven dots at a first-year's, then eight or
-- nine, then ten or more -- and at a doctorate by what the numbers say: they
-- still rise along the outline but skip as they go (3, 5, 9, 10...), so the
-- next dot is the next number *up*, which has to be looked for.
local J = {}
J.__index = J

local DOT_U = 11        -- one step of a picture's grid, in page pixels
local DOT_TOUCH = 5     -- how near the pen must come to a dot to touch it
local DOT_TRIES = 3
local DOT_FLASH = 0.45
local DOT_FADE = 1.4
local WANDER = 14       -- how far the dots drift as they go
-- Semitones off the note's G, a step up the pentatonic per dot joined.
local RISE = { -12, -10, -8, -5, -3, 0, 2, 4, 7, 9, 12, 14 }

-- Each picture is its outline's corners in order, on a grid ten across and
-- eight down, and closes back on its first.
local PICTURES = {
    fish = { { 10, 4 }, { 7, 1 }, { 3, 2 }, { 0, 0 }, { 0, 8 }, { 3, 6 }, { 7, 7 } },
    arrow = { { 0, 3 }, { 6, 3 }, { 6, 0 }, { 10, 4 }, { 6, 8 }, { 6, 5 }, { 0, 5 } },
    bolt = { { 4, 0 }, { 9, 0 }, { 6, 3 }, { 9, 3 }, { 1, 8 }, { 4, 4 }, { 1, 4 } },
    sail = { { 5, 0 }, { 8, 5 }, { 10, 5 }, { 8, 8 }, { 2, 8 }, { 0, 5 }, { 2, 5 } },
    heart = { { 5, 2 }, { 7, 0 }, { 9, 1 }, { 10, 3 }, { 5, 8 }, { 0, 3 }, { 1, 1 }, { 3, 0 } },
    cat = { { 1, 8 }, { 0, 4 }, { 1, 0 }, { 4, 2 }, { 6, 2 }, { 9, 0 }, { 10, 4 }, { 9, 8 } },
    house = { { 1, 8 }, { 1, 4 }, { 5, 0 }, { 9, 4 }, { 9, 8 }, { 6, 8 }, { 6, 5 }, { 4, 5 }, { 4, 8 } },
    crown = { { 0, 8 }, { 0, 2 }, { 2, 5 }, { 3, 1 }, { 5, 4 }, { 7, 1 }, { 8, 5 }, { 10, 2 }, { 10, 8 } },
    star = { { 5, 0 }, { 6, 3 }, { 10, 3 }, { 7, 5 }, { 8, 8 }, { 5, 6 }, { 2, 8 }, { 3, 5 }, { 0, 3 }, { 4, 3 } },
    tree = { { 5, 0 }, { 8, 3 }, { 6, 3 }, { 9, 6 }, { 6, 6 }, { 6, 8 }, { 4, 8 }, { 4, 6 }, { 1, 6 }, { 4, 3 }, { 2, 3 } },
    rocket = { { 5, 0 }, { 7, 2 }, { 7, 6 }, { 9, 8 }, { 6, 7 }, { 4, 7 }, { 1, 8 }, { 3, 6 }, { 3, 2 } },
}

local DOT_SETS = {
    school = { "fish", "arrow", "bolt", "sail" },
    bachelor = { "heart", "cat", "house", "crown", "rocket" },
    masters = { "star", "tree", "house", "crown", "rocket" },
    phd = { "star", "tree", "house", "crown", "rocket", "heart", "cat" },
}

function J.new(x, y, courseKey)
    local set = DOT_SETS[courseKey] or DOT_SETS.school
    local pic = PICTURES[set[love.math.random(#set)]]
    local flip = love.math.random() < 0.5
    local x0, y0 = math.floor(x - 5 * DOT_U), math.floor(y - 4 * DOT_U)
    local dots, sx, sy = {}, 0, 0
    -- Mirrored half the time, and started at any corner, so a picture seen
    -- twice is not the same walk twice.
    local start = love.math.random(#pic) - 1
    for k = 1, #pic do
        local c = pic[(k - 1 + start) % #pic + 1]
        local gx = flip and 10 - c[1] or c[1]
        dots[k] = { x = x0 + gx * DOT_U, y = y0 + c[2] * DOT_U }
        sx, sy = sx + dots[k].x, sy + dots[k].y
    end
    local cx, cy = sx / #dots, sy / #dots

    -- The numbers: one, two, three -- or at a doctorate a climb with gaps in it.
    local n = 0
    for k, d in ipairs(dots) do
        n = courseKey == "phd" and n + love.math.random(1, 4) or k
        d.label = tostring(n)
        -- Beside the dot, on the side away from the middle of the picture.
        local ux, uy = util.normalize(d.x - cx, d.y - cy)
        d.lx = math.floor(d.x + ux * 6 - Font.width(d.label) / 2 + 0.5)
        d.ly = math.floor(d.y + uy * 6 - Font.height / 2 + 0.5)
        d.wx, d.wy = ux, uy
    end

    return setmetatable({
        kind = "dots",
        x = x, y = y, cx = cx, cy = cy,
        hw = 5 * DOT_U + 10, hh = 4 * DOT_U + 10,
        dots = dots,
        joined = 0,
        tries = DOT_TRIES,
        state = "open",
        seed = util.hash01(x, y, 8) * 1000,
    }, J)
end

function J:dotAt(px, py)
    local best, bestD
    for i, d in ipairs(self.dots) do
        local dd = util.len(px - d.x, py - d.y)
        if dd <= DOT_TOUCH and (not bestD or dd < bestD) then best, bestD = i, dd end
    end
    return best
end

-- Arriving on dot `i` with the pen.
function J:touch(i, game)
    if i <= self.joined then return end -- passing back over the picture is free
    if i == self.joined + 1 then
        self.joined = i
        -- Up a step of the pentatonic with every dot, so a picture being
        -- joined is heard rising and never sounds a wrong note on the way.
        Sfx.play("note", 2 ^ ((RISE[i] or RISE[#RISE]) / 12))
        if i == #self.dots then
            self.state = "won"
            self.t = 0
            local p = Pickup.new("star", self.cx, self.cy)
            game.pickups[#game.pickups + 1] = p
            game.particles:burst(self.cx, self.cy, 10, Palette.red)
            shout(game, "WELL DRAWN!", self.cx, self.y - 4 * DOT_U - 4, Palette.blue)
            Sfx.play("accept")
        end
        return
    end
    -- Out of order: the lines come off and it starts again from the first.
    self.flash, self.flashT = i, DOT_FLASH
    self.joined = 0
    self.tries = self.tries - 1
    game:say("WRONG DOT!")
    Sfx.play("stamp")
    if self.tries <= 0 then
        self.state = "fading"
        self.t = 0
        shout(game, "WANDERED OFF!", self.cx, self.y - 4 * DOT_U - 4, Palette.red)
    end
    return true
end

function J:update(dt, game, pen)
    if self.flashT then
        self.flashT = self.flashT - dt
        if self.flashT <= 0 then self.flash, self.flashT = nil, nil end
    end
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= DOT_FADE then self.state = "gone" end
        return
    end
    if self.state ~= "open" then return end

    if not pen then
        self.penX, self.penY, self.on = nil, nil, nil
        return
    end
    local x0, y0 = self.penX or pen.x, self.penY or pen.y
    local dx, dy = pen.x - x0, pen.y - y0
    local steps = math.max(1, math.ceil(util.len(dx, dy)))
    for s = 0, steps do
        -- A dot is touched as the pen arrives on it, not while it rests there.
        local i = self:dotAt(x0 + dx * s / steps, y0 + dy * s / steps)
        if i and i ~= self.on then
            self.on = i
            if self:touch(i, game) or self.state ~= "open" then break end
        elseif not i then
            self.on = nil
        end
    end
    self.penX, self.penY = pen.x, pen.y
end

function J:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / DOT_FADE, 0, 1) or 0
    fadeSeed = self.seed
    local drift = fade * WANDER

    -- The lines joined so far, ruled straight, and the outline closed once done.
    colour(Palette.ink)
    local n = self.state == "won" and #self.dots or self.joined
    for k = 1, n - 1 do
        local a, b = self.dots[k], self.dots[k + 1]
        pixelart.line(a.x, a.y, b.x, b.y)
    end
    if self.state == "won" then
        local a, b = self.dots[#self.dots], self.dots[1]
        pixelart.line(a.x, a.y, b.x, b.y)
    end

    for i, d in ipairs(self.dots) do
        local x = d.x + d.wx * drift * (0.5 + util.hash01(i, 1, self.seed))
        local y = d.y + d.wy * drift * (0.5 + util.hash01(i, 2, self.seed))
        local wrong = self.flash == i
        colour(wrong and Palette.red or i <= self.joined and Palette.blue or Palette.ink)
        rect(x - 1, y - 1, 2, 2)
        if wrong then
            colour(Palette.red)
            scribble(x, y, DOT_TOUCH, 1)
        end
        if self.state ~= "won" and fade < 0.6 then
            colour(i <= self.joined and Palette.blue or Palette.slate)
            Font.print(d.label, d.lx + (x - d.x), d.ly + (y - d.y))
        end
    end

    -- Tries left, as tally strokes in the corner; a spent one goes red.
    if self.state ~= "won" then
        local tx, ty = math.floor(self.x + 5 * DOT_U + 4), math.floor(self.y - 4 * DOT_U - 2)
        for k = 1, DOT_TRIES do
            colour(k <= DOT_TRIES - self.tries and Palette.red or Palette.slate)
            rect(tx + k * 3, ty, 1, 5)
        end
    end
    fade = 0
end

--- the portrait ----------------------------------------------------------------------

-- ART's second sheet, and the opposite of the first: join the dots is moving
-- with care, this is not moving at all. An easel and a chalk cross on the floor
-- beside it. Step onto the cross and the portrait starts -- yours, drawn off the
-- hero you play as (`Sprites.player`, whatever the studio has made of it), a
-- row at a time onto the easel's canvas -- and you have to sit for it: walk off
-- the cross before it is finished and it smears, and the sheet fades.
--
-- The dodgeball pit's drill turned inside out. You may draw, and every tool
-- goes on fighting for you, and being hit does not spoil it -- only walking
-- does -- so the horde walks straight up to a hero who has promised not to step
-- aside, and the question is whether what you carry holds them off for the
-- sitting. Finished, the alarm clock drops at your feet: the crowd that
-- gathered round a sitter is exactly the crowd it was made for.
local P = {}
P.__index = P

local SIT = { school = 6, bachelor = 7, masters = 8, phd = 9 }
local MARK_R = 7          -- the chalk circle: inside it is sitting
local MARK_IN = 4         -- and this near its middle starts the sitting
local EASEL_GAP = 34      -- from the easel's middle to the cross
local PORTRAIT_FADE = 1.2
local SIT_STROKE = 0.45   -- how often a brush is heard while it paints

-- The hero, whoever is being played: the rows the studio's drawing was compiled
-- from, or a stick man if a sprite somehow has none.
local function heroRows()
    local s = Sprites.player
    return s and s.rows or Sprites.STICKMAN
end

function P.new(x, y, courseKey)
    local rows = heroRows()
    local w, h = #rows[1], #rows
    local scale = (w <= 16 and h <= 20) and 2 or 1
    local cw, ch = w * scale + 4, h * scale + 4 -- the canvas, a margin round it
    local ex = math.floor(x - EASEL_GAP / 2 - cw / 2)
    local ey = math.floor(y - ch / 2 - 6)
    return setmetatable({
        kind = "portrait",
        x = x, y = y,
        hw = EASEL_GAP / 2 + cw / 2 + MARK_R + 4, hh = ch / 2 + 16,
        rows = rows, scale = scale,
        ex = ex, ey = ey, cw = cw, ch = ch,
        mx = math.floor(x + EASEL_GAP / 2 + cw / 2 - 4), my = math.floor(y + 4),
        time = SIT[courseKey] or SIT.school,
        state = "open",
        seed = util.hash01(x, y, 9) * 1000,
    }, P)
end

function P:sitting(px, py, r)
    return util.len(px - self.mx, py - self.my) <= r
end

function P:finish(game, won)
    self.live = false
    if won then
        self.state = "won"
        game.pickups[#game.pickups + 1] = Pickup.new("alarm", self.mx, self.my + 10)
        game.particles:burst(self.ex + self.cw / 2, self.ey + self.ch / 2, 10, Palette.red)
        shout(game, "MASTERPIECE!", self.ex + self.cw / 2, self.ey - 6, Palette.blue)
        Sfx.play("accept")
    else
        self.state, self.t = "fading", 0
        self.leftAt = self.left
        shout(game, "SMUDGED!", self.ex + self.cw / 2, self.ey - 6, Palette.red)
        Sfx.play("eraser")
    end
end

function P:update(dt, game)
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= PORTRAIT_FADE then self.state = "gone" end
        return
    end
    if self.state ~= "open" then return end

    local p = game.player
    if not self.live then
        if self:sitting(p.x, p.y, MARK_IN) then
            self.live = true
            self.left = self.time
            self.brush = 0
            game:say("HOLD STILL!")
            Sfx.play("tick")
        end
        return
    end

    if not self:sitting(p.x, p.y, MARK_R) then
        self:finish(game, false)
        return
    end
    self.left = self.left - dt
    self.brush = self.brush - dt
    if self.brush <= 0 then
        self.brush = SIT_STROKE
        Sfx.play("brush" .. love.math.random(6))
    end
    if self.left <= 0 then self:finish(game, true) end
end

function P:clock()
    return self.live and self.left
end

function P:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / PORTRAIT_FADE, 0, 1) or 0
    fadeSeed = self.seed

    local ex, ey, cw, ch = self.ex, self.ey, self.cw, self.ch
    -- The easel: three legs and the ledge the canvas stands on.
    colour(Palette.slate)
    local mid = ex + math.floor(cw / 2)
    for k = 0, 9 do
        dot(ex + 3 - math.floor(k / 3), ey + ch + k)
        dot(ex + cw - 4 + math.floor(k / 3), ey + ch + k)
        dot(mid, ey + ch + k)
    end
    rect(ex - 2, ey + ch, cw + 4, 1)
    rect(mid, ey - 3, 1, 3)

    -- The canvas.
    colour(Palette.ink)
    rect(ex, ey, cw, 1)
    rect(ex, ey + ch - 1, cw, 1)
    rect(ex, ey, 1, ch)
    rect(ex + cw - 1, ey, 1, ch)

    -- The portrait, as far as it has got: the hero's pixels in reading order,
    -- the one being drawn in graphite as the pencil's point.
    local rows, s = self.rows, self.scale
    local w, h = #rows[1], #rows
    -- All of it once won; as far as the clock has got while sitting; and a
    -- smudged one fades from where it had got to, not from finished.
    local done = w * h
    if self.state == "open" then
        done = self.live and math.floor((1 - self.left / self.time) * w * h) or 0
    elseif self.state == "fading" then
        done = math.floor((1 - (self.leftAt or 0) / self.time) * w * h)
    end
    local n = 0
    for r = 1, h do
        local row = rows[r]
        for c = 1, w do
            n = n + 1
            if n > done then break end
            local ch_ = row:sub(c, c)
            if ch_ ~= "." and Palette.key[ch_] then
                colour(n == done and self.live and Palette.graphite or Palette.key[ch_])
                rect(ex + 2 + (c - 1) * s, ey + 2 + (r - 1) * s, s, s)
            end
        end
        if n > done then break end
    end

    -- The chalk cross and the circle round it: where to sit.
    if self.state ~= "won" then
        colour(self.live and Palette.red or Palette.slate)
        for k = -2, 2 do
            dot(self.mx + k, self.my + k)
            dot(self.mx + k, self.my - k)
        end
        scribble(self.mx, self.my, MARK_R, 1, true)
    end
    fade = 0
end

--- the market ------------------------------------------------------------------------

-- FINANCE's second sheet, and the one in the book played with real money. A
-- price chart ruled on the page over a BUY box and a SELL box. Walk onto the
-- sheet and the market opens: the price draws itself left to right against a
-- clock. Step into BUY and you put coins in -- the ones this run has picked up
-- first, then the purse's own -- at the price on the chart; step into SELL and
-- they come back out at the price then, as coins on the page. Buy low and sell
-- high and you walk off with more than you put in; sell low and you walk off
-- with less; still holding when the chart reaches its edge and the stake is
-- gone. One trade a sheet.
--
-- That is the whole of its price and its prize, which is why it pays nothing
-- else and sends nothing: a stake is already a gamble, and it is the one sheet
-- whose loss outlives the run the way the till's coins do. It climbs the
-- course by the stake and by the chart: a first-year's wanders gently and
-- slowly, and up the ladder it gets jumpier and quicker, and at a doctorate it
-- crashes once somewhere after the middle -- and only a quick seller beats it.
local K = {}
K.__index = K

local CHART_W, CHART_H = 120, 44
local CHART_UP = 26        -- the chart's middle, above the sheet's
local BOX_DOWN = 20        -- the boxes' middles, below it
local BOX_APART = 36       -- each box's middle off the sheet's middle line
local BOX_H = 18
local POINTS = 49          -- prices on the chart, one every CHART_W / 48 px
local LO, HI = 20, 99      -- what a price can be
local STAKE = { school = 3, bachelor = 4, masters = 5, phd = 6 }
local OPEN_FOR = { school = 16, bachelor = 14, masters = 12, phd = 12 }
local SWING = { school = 4, bachelor = 6, masters = 8, phd = 9 }
local MARKET_FADE = 1.2

-- The day's prices, dealt when the sheet is printed: a walk that leans back
-- towards the middle so it never sits on a rail for long, and at a doctorate
-- one crash, a third off over three steps, after the middle.
local function market(courseKey)
    local swing = SWING[courseKey] or SWING.school
    local p = love.math.random(40, 65)
    local prices = { p }
    local crash = courseKey == "phd" and love.math.random(26, 38) or nil
    for i = 2, POINTS do
        local pull = (60 - p) * 0.06
        p = p + pull + (love.math.random() * 2 - 1) * swing
        if crash and i >= crash and i < crash + 3 then p = p * 0.86 end
        p = util.clamp(p, LO, HI)
        prices[i] = p
    end
    return prices
end

function K.new(x, y, courseKey)
    local buyW = math.max(36, Font.width(I18n.t("BUY")) + 10)
    local sellW = math.max(36, Font.width(I18n.t("SELL")) + 10)
    local k = setmetatable({
        kind = "stocks",
        x = x, y = y,
        hw = math.max(CHART_W / 2 + 6, BOX_APART + math.max(buyW, sellW) / 2 + 2),
        hh = CHART_UP + CHART_H / 2 + 8,
        prices = market(courseKey),
        stake = STAKE[courseKey] or STAKE.school,
        time = OPEN_FOR[courseKey] or OPEN_FOR.school,
        cl = math.floor(x - CHART_W / 2), ct = math.floor(y - CHART_UP - CHART_H / 2),
        buy = { x = x - BOX_APART, y = y + BOX_DOWN, w = buyW, label = "BUY" },
        sell = { x = x + BOX_APART, y = y + BOX_DOWN, w = sellW, label = "SELL" },
        state = "open",
        seed = util.hash01(x, y, 10) * 1000,
    }, K)
    k.hh = math.max(k.hh, BOX_DOWN + BOX_H / 2 + 12)
    -- The chart is scaled to the day's own range and a little over, so a quiet
    -- first-year's market still fills its height and a move reads as a move;
    -- the price printed at the line's head is what says how much it is.
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(k.prices) do lo, hi = math.min(lo, v), math.max(hi, v) end
    local pad = math.max(4, (hi - lo) * 0.1)
    k.lo, k.hi = lo - pad, hi + pad
    return k
end

function K:within(box, px, py)
    return math.abs(px - box.x) <= box.w / 2 - 1 and math.abs(py - box.y) <= BOX_H / 2 - 1
end

-- How far along the chart is, in prices, and the price there.
function K:at()
    local f = util.clamp(1 - (self.left or self.time) / self.time, 0, 1) * (POINTS - 1) + 1
    local i = math.floor(f)
    local a, b = self.prices[i], self.prices[math.min(POINTS, i + 1)]
    return f, a + (b - a) * (f - i)
end

function K:px(f) return self.cl + (f - 1) * CHART_W / (POINTS - 1) end
function K:py(p)
    return self.ct + CHART_H - 1 - (p - self.lo) / (self.hi - self.lo) * (CHART_H - 2)
end

-- Coins to the stake, off the run's first and the purse's after; how many
-- were found, which may be fewer than asked for or none at all.
function K:fund(game)
    local want = self.stake
    local fromRun = math.min(want, game.banked or 0)
    local fromPurse = math.min(want - fromRun, Purse.total or 0)
    if fromRun + fromPurse <= 0 then return 0 end
    if fromPurse > 0 and not Purse.spend(fromPurse) then fromPurse = 0 end
    game.banked = (game.banked or 0) - fromRun
    return fromRun + fromPurse
end

function K:close(game, text)
    self.live = false
    self.state, self.t = "fading", 0
    shout(game, text, self.x, self.ct - 4, Palette.red)
    Sfx.play("stamp")
end

function K:update(dt, game)
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= MARKET_FADE then self.state = "gone" end
        return
    end
    if self.state ~= "open" then return end

    local p = game.player
    if not self.live then
        if math.abs(p.x - self.x) <= self.hw and math.abs(p.y - self.y) <= self.hh then
            self.live = true
            self.left = self.time
            game:say("MARKET OPEN!")
            Sfx.play("tick")
        end
        return
    end

    self.left = self.left - dt
    if self.left <= 0 then
        self.left = 0
        -- Still holding is the stake gone; never having bought is nothing lost.
        self:close(game, "MARKET CLOSED!")
        return
    end

    local f, price = self:at()
    local inBuy, inSell = self:within(self.buy, p.x, p.y), self:within(self.sell, p.x, p.y)
    if inBuy and not self.wasBuy and not self.held then
        local coins = self:fund(game)
        if coins > 0 then
            self.held, self.boughtAt, self.boughtF = coins, price, f
            game.particles:burst(self.buy.x, self.buy.y, 6, Palette.blush)
            game:say("BOUGHT!")
            Sfx.play("item")
        elseif not self.broke then
            self.broke = true
            game:say("NO COINS")
            Sfx.play("stamp")
        end
    elseif inSell and not self.wasSell and self.held then
        local back = math.floor(self.held * price / self.boughtAt + 0.5)
        self.soldAt, self.soldF = price, f
        self.live = false
        self.state = "done"
        -- Paid out as coins on the page under the box, in rows of five, to be
        -- walked over -- the till's way, so the money is seen to come back.
        for c = 0, back - 1 do
            local cx = self.sell.x + ((c % 5) - 2) * 8
            local cy = self.sell.y + BOX_H / 2 + 6 + math.floor(c / 5) * 8
            game.pickups[#game.pickups + 1] = Pickup.new("coin", cx, cy)
        end
        game.particles:burst(self.sell.x, self.sell.y, 10, Palette.blush)
        -- The verdict is the trade's, said in a word: more back than went in,
        -- less, or exactly what you paid.
        shout(game, back > self.held and "PROFIT!" or back < self.held and "LOSS!"
            or "SOLD!", self.x, self.ct - 4,
            back < self.held and Palette.red or Palette.blue)
        Sfx.play(back > self.held and "accept" or "stamp")
    end
    self.wasBuy, self.wasSell = inBuy, inSell
end

function K:clock()
    return self.live and self.left
end

function K:drawBox(box, lit)
    local l, t = math.floor(box.x - box.w / 2), math.floor(box.y - BOX_H / 2)
    colour(lit and Palette.blue or Palette.slate)
    rect(l, t, box.w, 1)
    rect(l, t + BOX_H - 1, box.w, 1)
    rect(l, t, 1, BOX_H)
    rect(l + box.w - 1, t, 1, BOX_H)
    if fade < 0.6 then
        love.graphics.setColor(lit and Palette.blue or Palette.ink)
        Font.printCentered(I18n.t(box.label), box.x, t + math.floor((BOX_H - Font.height) / 2))
    end
end

function K:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / MARKET_FADE, 0, 1) or 0
    fadeSeed = self.seed

    -- The chart's axes, and a tick along the bottom every quarter of the day.
    local cl, ct = self.cl, self.ct
    colour(Palette.slate)
    rect(cl - 1, ct, 1, CHART_H)
    rect(cl - 1, ct + CHART_H, CHART_W + 2, 1)
    for q = 1, 4 do rect(cl + q * CHART_W / 4, ct + CHART_H + 1, 1, 2) end

    -- What was paid, ruled across the chart dotted, so above it is profit.
    if self.boughtAt then
        colour(Palette.graphite)
        local by = math.floor(self:py(self.boughtAt))
        for xx = cl, cl + CHART_W - 1, 3 do dot(xx, by) end
    end

    -- The price so far: blue while it is above what you paid, red below.
    local upto = self.live and self:at()
        or self.soldF or (self.state == "fading" and POINTS) or 1
    local last
    for i = 1, math.floor(upto) do
        local x, y = self:px(i), self:py(self.prices[i])
        if last then
            local above = not self.boughtAt or self.prices[i] >= self.boughtAt
            colour((self.boughtF and i > self.boughtF and not above) and Palette.red
                or Palette.ink)
            if fade == 0 then pixelart.line(last.x, last.y, x, y) end
        end
        last = { x = x, y = y }
    end
    if self.live or self.soldF then
        local f, price = self:at()
        if self.soldF then f, price = self.soldF, self.soldAt end
        local x, y = self:px(f), self:py(price)
        if last and fade == 0 then
            colour(Palette.ink)
            pixelart.line(last.x, last.y, x, y)
        end
        -- The price now, at the head of the line, in the corner above it.
        love.graphics.setColor(Palette.ink)
        Font.printRight(tostring(math.floor(price + 0.5)), cl + CHART_W, ct - Font.height - 2)
        colour(Palette.red)
        rect(x - 1, y - 1, 3, 3)
    end
    if self.boughtF then
        colour(Palette.blue)
        rect(self:px(self.boughtF) - 1, self:py(self.boughtAt) - 1, 3, 3)
    end

    if self.state ~= "done" then
        self:drawBox(self.buy, self.held ~= nil)
        self:drawBox(self.sell, false)
    end
    fade = 0
end

--- hangman -----------------------------------------------------------------------

-- GRAMMAR's sheet. A gallows, a word with three of its letters left out, and a
-- few more letters ruled out on the page under it than the word wants -- the
-- three it is missing among some it is not (src/quiz.lua, Quiz.hangman). It is
-- answered the boards' way, standing on a letter until the ring round it has
-- drawn: a right one is written into its gap, a wrong one is struck out and
-- draws a piece of the man on the gallows. Three right is the word, and a
-- diamond (the boards' top prize, through `award`).
--
-- Three wrong is the whole man, and then he climbs down: the figure drawn on
-- the rope comes off it as a monster of his own (`stickman` in Enemy.types)
-- and comes for you. That is the price and the second chance at once -- kill
-- him and he leaves a heart where he fell. A heart and never the prize the
-- word was worth, and put down as itself rather than through `award`, which
-- would make it a diamond again at a master's: the consolation has to stay a
-- step down or it is not one, and a sheet you could fail on purpose for the
-- same pay would be a sheet with no question on it.
--
-- Three wrong rather than the six limbs of the playground game, because there
-- are only five decoys at most and the horde is the clock: a head, a body with
-- its arms, and the legs.

local G = {}
G.__index = G

local PITCH = 6           -- one letter of the word: three of glyph, gaps either side
local PAD_GAP = 22        -- between letters to stand on
local PAD_RX, PAD_RY = 8, 6
local PADS_DOWN = 12      -- the first row of letters below the sheet's middle
local PAD_ROW = 18        -- and the second below that
local MISSES = 3          -- wrong letters before he is hanged
local LET_DOWN = 0.8      -- seconds he swings there before he climbs down
local HANG_FADE = 1.2
local GALLOWS = -40       -- the post's foot, off the sheet's middle
local WORD_AT = 16        -- the word's middle, off the sheet's middle

function G.new(x, y, courseKey, lang)
    local word = Quiz.hangman(courseKey, lang)
    local g = setmetatable({
        kind = "hangman",
        x = x, y = y,
        chars = word.chars, gaps = word.gaps,
        filled = {},
        pads = {},
        misses = 0,
        state = "open",
        gx = x + GALLOWS,
        seed = util.hash01(x, y, 11) * 1000,
    }, G)
    -- Where the man hangs: what is drawn there, and where he climbs down from.
    g.mx, g.my = g.gx + 14, y - 15

    -- The letters in a row, or two rows staggered by half a gap once there are
    -- more than four, so a sheet never spans more than four of them.
    local n = #word.choices
    local top = n <= 4 and n or math.ceil(n / 2)
    for i, ch in ipairs(word.choices) do
        local row, k, m = 0, i - 1, top
        if i > top then row, k, m = 1, i - 1 - top, n - top end
        g.pads[i] = {
            ch = ch,
            x = x + (k - (m - 1) / 2) * PAD_GAP,
            y = y + PADS_DOWN + row * PAD_ROW,
            hold = 0,
        }
    end

    g.wx = math.floor(x + WORD_AT - (#g.chars * PITCH - 1) / 2)
    local right = math.max(g.wx + #g.chars * PITCH, x + (top - 1) / 2 * PAD_GAP + PAD_RX)
    g.hw = math.max(x - (g.gx - 12), right - x) + 2
    g.hh = PADS_DOWN + PAD_ROW + PAD_RY + 2
    return g
end

function G:standingOn(px, py)
    for i, p in ipairs(self.pads) do
        if not p.given then
            local dx, dy = (px - p.x) / PAD_RX, (py - p.y) / PAD_RY
            if dx * dx + dy * dy <= 1 then return i end
        end
    end
end

function G:give(i, game)
    local p = self.pads[i]
    p.given = true
    for k, ch in ipairs(self.chars) do
        if self.gaps[k] and ch == p.ch then
            self.filled[k] = true
            p.right = true
        end
    end

    local top = self.y - 30
    if p.right then
        local done = true
        for k in pairs(self.gaps) do
            if not self.filled[k] then done = false end
        end
        if done then
            self.state = "won"
            -- Over the word it paid for, between it and the letters, like the
            -- boards' prize: a step away rather than under your feet.
            award(game, "diamond", self.x + WORD_AT, self.y - 6)
            shout(game, "SOLVED!", self.x, top, Palette.blue)
            Sfx.play("accept")
        else
            Sfx.play("tick")
        end
        return
    end

    self.misses = self.misses + 1
    game.particles:burst(p.x, p.y, 8, Palette.red)
    Sfx.play("stamp")
    if self.misses >= MISSES then
        self.state, self.t = "hanging", 0
        shout(game, "HANGED!", self.x, top, Palette.red)
    end
end

function G:update(dt, game)
    if self.state == "fading" then
        self.t = self.t + dt
        if self.t >= HANG_FADE then self.state = "gone" end
        return
    end

    if self.state == "hanging" then
        self.t = self.t + dt
        if self.t >= LET_DOWN then
            -- Off the rope and onto the page, where he was drawn. Live from
            -- here, so the sheet hears about him wherever the fight goes.
            self.man = game:spawnEnemy("stickman", self.mx, self.my)
            self.state, self.live = "loose", true
            game.particles:burst(self.mx, self.my, 8, Palette.ink)
            Sfx.play("eraser")
        end
        return
    end

    if self.state == "loose" then
        local man = self.man
        if not man.gone then return end
        self.live = false
        -- Killed, a heart where he fell; outrun and forgotten by the page
        -- (Game:updateEnemies' despawn), nothing. Either way the sheet goes.
        if man.killed then
            game.pickups[#game.pickups + 1] = Pickup.new("heart", man.x, man.y)
            game.particles:burst(man.x, man.y, 10, Palette.red)
            shout(game, "CUT DOWN!", man.x, man.y - 14, Palette.blue)
            Sfx.play("accept")
        end
        self.state, self.t = "fading", 0
        return
    end

    if self.state ~= "open" then return end

    local on = self:standingOn(game.player.x, game.player.y)
    for i, p in ipairs(self.pads) do
        if i == on then
            p.hold = p.hold + dt / HOLD
        else
            p.hold = math.max(0, p.hold - dt * DRAIN / HOLD)
        end
    end
    if on and self.pads[on].hold >= 1 then self:give(on, game) end
end

-- The boards' ring (`ring` above), squashed to an answer's ellipse and plotted
-- through the fade.
local function oval(cx, cy, rx, ry, p, dotted)
    local n = math.floor(2 * math.pi * math.max(rx, ry) * 1.5)
    for k = 0, math.floor(n * util.clamp(p, 0, 1)) - 1 do
        if not dotted or k % 4 == 0 then
            local a = -math.pi / 2 + 2 * math.pi * k / n
            local c, s = math.cos(a), math.sin(a)
            dot(cx + c * rx + 0.5, cy + s * ry + 0.5)
            if not dotted then dot(cx + c * (rx + 1) + 0.5, cy + s * (ry + 1) + 0.5) end
        end
    end
end

-- A stroke a pixel wide, through the fade: the man is drawn in these.
local function stroke(ax, ay, bx, by)
    local n = math.max(math.abs(bx - ax), math.abs(by - ay))
    for k = 0, n do dot(ax + (bx - ax) * k / n + 0.5, ay + (by - ay) * k / n + 0.5) end
end

-- One letter of the face, through the fade's colour (the face is an atlas, so
-- it steps down the ramp but does not drop out a pixel at a time).
local function letter(ch, x, y)
    if fade < 1 then Font.print(ch, x, y) end
end

function G:drawMan(x, y, parts)
    -- Swinging, a pixel either way, while he is about to come down.
    if self.state == "hanging" then
        x = x + (math.floor(self.t * 12) % 2 == 0 and -1 or 1)
    end
    if parts >= 1 then
        for k = 0, 15 do
            local a = 2 * math.pi * k / 16
            dot(x + math.cos(a) * 3 + 0.5, y - 6 + math.sin(a) * 3 + 0.5)
        end
    end
    if parts >= 2 then
        stroke(x, y - 2, x, y + 4)
        stroke(x - 3, y, x + 3, y)
    end
    if parts >= 3 then
        stroke(x, y + 4, x - 3, y + 8)
        stroke(x, y + 4, x + 3, y + 8)
    end
end

function G:draw()
    if self.state == "gone" then return end
    fade = self.state == "fading" and util.clamp(self.t / HANG_FADE, 0, 1) or 0
    fadeSeed = self.seed

    -- The gallows: a foot, a post, a beam and the rope.
    local gx, y = self.gx, self.y
    colour(Palette.slate)
    rect(gx - 10, y + 2, 20, 1)
    rect(gx - 6, y - 28, 1, 30)
    rect(gx - 6, y - 28, 21, 1)
    stroke(gx - 5, y - 23, gx, y - 27)
    rect(self.mx, y - 27, 1, 3)

    -- The man, as far as the wrong letters have drawn him, until he is down.
    if self.state ~= "loose" and self.state ~= "fading" then
        colour(self.state == "hanging" and Palette.red or Palette.ink)
        self:drawMan(self.mx, self.my, self.misses)
    end

    -- The word: every letter on its line, the gaps empty until stood for --
    -- yours written in blue, and once he is hanged the ones you missed in red.
    for k, ch in ipairs(self.chars) do
        local sx = self.wx + (k - 1) * PITCH
        colour(Palette.slate)
        rect(sx, y - 15, 5, 1)
        if not self.gaps[k] then
            colour(Palette.ink)
            letter(ch, sx + 1, y - 22)
        elseif self.filled[k] then
            colour(Palette.blue)
            letter(ch, sx + 1, y - 22)
        elseif self.misses >= MISSES then
            colour(Palette.red)
            letter(ch, sx + 1, y - 22)
        end
    end

    -- The letters to stand on, the boards' way: a dotted ring where to stand
    -- and a blue one drawing while you do; given, ringed blue if it was in the
    -- word and red and struck out if it was not.
    for _, p in ipairs(self.pads) do
        local spent = p.given or self.state ~= "open"
        colour(spent and not p.given and Palette.graphite or Palette.ink)
        letter(p.ch, p.x - 1, p.y - 2)
        if p.right then
            colour(Palette.blue)
            oval(p.x, p.y, PAD_RX, PAD_RY, 1)
        elseif p.given then
            colour(Palette.red)
            oval(p.x, p.y, PAD_RX, PAD_RY, 1)
            stroke(p.x - 4, p.y + 3, p.x + 4, p.y - 3)
        elseif not spent then
            colour(Palette.graphite)
            oval(p.x, p.y, PAD_RX, PAD_RY, 1, true)
            if p.hold > 0 then
                colour(Palette.blue)
                oval(p.x, p.y, PAD_RX, PAD_RY, p.hold)
            end
        end
    end
    fade = 0
end

--- the page ------------------------------------------------------------------------

local KINDS = {
    tictactoe = function(x, y) return T.new(x, y) end,
    simon = function(x, y, game)
        return S.new(x, y, game.course.key, game.subject.paper and game.subject.paper.staff)
    end,
    dodgeball = function(x, y, game) return D.new(x, y, game.course.key, daysOf(game)) end,
    -- Back empty, like Simon, when no path was dealt; the cell is spent anyway.
    hopscotch = function(x, y, game) return H.new(x, y, game.course.key, daysOf(game)) end,
    circuit = function(x, y, game) return C.new(x, y, game.course.key) end,
    dots = function(x, y, game) return J.new(x, y, game.course.key) end,
    portrait = function(x, y, game) return P.new(x, y, game.course.key) end,
    stocks = function(x, y, game) return K.new(x, y, game.course.key) end,
    -- In the language the book is being read in: the one sheet with words.
    hangman = function(x, y, game) return G.new(x, y, game.course.key, I18n.lang) end,
}
-- For a test harness to build one kind directly, and for nothing in the game.
Worksheet._kinds = KINDS
for kind in pairs(BOARDS) do
    KINDS[kind] = function(x, y, game) return Q.new(x, y, game.course.key, kind) end
end

function Worksheet.init(game)
    game.worksheets = {}
    game.worksheetCells = {}
    game.worksheetMix = game.subject.worksheets or DEFAULT_MIX
end

local function fixedAt(cx, cy, seed, mix)
    if util.hash01(cx, cy, seed + 21) >= DENSITY then return end
    return kindFor(mix, util.hash01(cx, cy, seed + 22)),
        (cx + 0.25 + util.hash01(cx, cy, seed + 23) * 0.5) * CELL,
        (cy + 0.25 + util.hash01(cx, cy, seed + 24) * 0.5) * CELL
end

-- Wake the sheets within reach that have not been printed yet. Each cell is
-- looked at once a run: printed, or found empty, it is never asked again.
-- Not during a boss fight -- the box is the fight, and a sheet printed into it
-- would be a prize nobody could stop for.
function Worksheet.materialize(game)
    if game.arena then return end
    local px, py = game.player.x, game.player.y
    for cy = math.floor((py - MATERIALIZE) / CELL),
             math.floor((py + MATERIALIZE) / CELL) do
        for cx = math.floor((px - MATERIALIZE) / CELL),
                 math.floor((px + MATERIALIZE) / CELL) do
            local key = cx * 100000 + cy
            if not game.worksheetCells[key] then
                local kind, x, y = fixedAt(cx, cy, game.pickupSeed, game.worksheetMix)
                if not kind then
                    game.worksheetCells[key] = true
                elseif util.len(x - px, y - py) < MATERIALIZE then
                    game.worksheetCells[key] = true
                    if util.len(x, y) > CLEAR_START then
                        -- A constructor may come back empty (Simon, when no
                        -- fair layout was dealt), and the cell is spent anyway.
                        game.worksheets[#game.worksheets + 1] = KINDS[kind](x, y, game)
                    end
                end
            end
        end
    end
end

function Worksheet.update(game, dt)
    Worksheet.materialize(game)

    -- The pen on the page, read the way Game:updateDrawing reads it -- through
    -- the steady camera, never the knocked one.
    local pen
    if Input.pointerDown then
        local left, top = Camera.steady()
        pen = { x = Input.pointerX + left, y = Input.pointerY + top }
    end

    local px, py = game.player.x, game.player.y
    for _, s in ipairs(game.worksheets) do
        -- And a sheet under way wherever you are: its clock and its rules do not
        -- stop because you walked off it (which is usually how it was lost).
        if s.live or (math.abs(s.x - px) < ACTIVE and math.abs(s.y - py) < ACTIVE) then
            s:update(dt, game, pen)
        end
    end
end

function Worksheet.draw(game)
    local left, top, w, h = Camera.bounds()
    for _, s in ipairs(game.worksheets) do
        if s.x + s.hw > left - 4 and s.x - s.hw < left + w + 4
            and s.y + s.hh > top - 4 and s.y - s.hh < top + h + 4 then
            s:draw()
        end
    end
end

-- What is left on the clock of the sheet under way, if one is, for the HUD to
-- hang under the run's own (P.E.'s pit and hopscotch).
function Worksheet.clock(game)
    for _, s in ipairs(game.worksheets or {}) do
        local left = s.clock and s:clock()
        if left then return math.max(0, left) end
    end
end

-- Whether a pickup at this point would land on a sheet, which the scatter
-- and the fixed pickups both ask before they put one down: a heart lying on a
-- tic-tac-toe cell is a prize and a puzzle each saying the other is not there.
function Worksheet.covers(game, x, y)
    if not game.worksheets then return false end
    for _, s in ipairs(game.worksheets) do
        if s.state == "gone" then -- nothing left on the page to land on
        elseif s.covers then
            if s:covers(x, y, PAD) then return true end
        elseif math.abs(x - s.x) < s.hw + PAD and math.abs(y - s.y) < s.hh + PAD then
            return true
        end
    end
    return false
end

return Worksheet
