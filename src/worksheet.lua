-- Worksheets: the little puzzles printed on the page, which pay a run for
-- stopping to solve one while the horde keeps coming (WORKSHEETS.md is the
-- idea list, README **Worksheets on the page** the argument).
--
-- Three machines today, each a row or more in KINDS:
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
-- by; an answer is a place you stand, or a row of places walked in order. All
-- three are things the game already asks you to do with your hands, so a
-- worksheet is a new question, not a new control.

local Palette = require("src.palette")
local Pickup = require("src.pickup")
local Quiz = require("src.quiz")
local Input = require("src.input")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local Sprites = require("src.sprites")
local util = require("src.util")

local Worksheet = {}

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
        game:say("THREE IN A ROW")
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
local function drop(kind, colour)
    return function(game, x, y)
        game.pickups[#game.pickups + 1] = Pickup.new(kind, x, y)
        game.particles:burst(x, y, 10, colour)
    end
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
    quiz = { book = Quiz.byCourse, right = drop("diamond", Palette.sky), wrong = giant },
    sequence = { book = Quiz.sequences, right = drop("heart", Palette.red), wrong = sting },
    science = { book = Quiz.science, right = drop("diamond", Palette.sky), wrong = giant },
    finance = { book = Quiz.finance, right = coins, wrong = giant },
    music = { book = Quiz.music, right = drop("heart", Palette.red), wrong = sting },
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
            game:say("CORRECT!")
            Sfx.play("accept")
        else
            self.row.wrong(game)
            game.particles:burst(self.answers[on].x, self.answers[on].y, 10, Palette.red)
            game:say("WRONG ANSWER")
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

-- A hand bell and four notes, each on a scrap of stave of its own. Ring the bell
-- -- walk onto it or draw over it -- and it plays a tune on the four, each note
-- lighting as it sounds; then walk the notes back in the same order. Right is a
-- heart. A wrong note sounds sour and starts you over, and the third one fades
-- the whole sheet off the page. Nothing else is lost: a failed Simon costs the
-- heart you did not get, which is the price of a sheet that asked nothing of you
-- but your ears and a few seconds.
--
-- It is the third way a sheet is answered -- not standing still, not drawing,
-- but walking through places in an order -- and so the layout is the rule: the
-- four sit on the corners of a square, which is the one arrangement where any
-- note can be walked to from any other without stepping on a third. The bell
-- sits above the square for the same reason, off every line between two notes.
--
-- It lights as well as sounds, so a phone on mute can still play it, and the
-- notes are written where they sit on a treble stave -- D, E, G and A, out of
-- the pentatonic, so any tune dealt off them is a tune -- so that higher on the
-- stave is higher in the ear, for a player who reads music. All four sit under
-- the middle line, which is what lets their stems go up as a stave writes
-- them: a stem hanging off the left of a head this small reads as a flag.

local S = {}
S.__index = S

local PAD_DX, PAD_TOP, PAD_BOTTOM = 20, -4, 28 -- the square, off the sheet's middle
local PAD_RX, PAD_RY = 13, 12
local LINE = 4      -- between a stave's lines, so a head fits a space
local BELL_Y = -28
local BELL_RX, BELL_RY = 8, 8
local LEAD = 0.35   -- the bell swings this long before the first note
local BEAT = 0.42   -- one note of the tune
local LIT = 0.3     -- how long a note stays lit, of its beat
local FLASH = 0.45  -- how long a wrong note stays red
local TRIES = 3
local FADE = 1.2

-- Semitones off G4 (the pitch src/sfx/note.mp3 is struck at, in the middle of
-- the four so no note is pitched far enough to drag), and the step each sits
-- on, counted up from the stave's middle line (B4): half a LINE apiece.
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

function S.new(x, y, courseKey)
    local s = setmetatable({
        kind = "simon",
        x = x, y = y,
        hw = PAD_DX + PAD_RX + 2,
        hh = math.max(-BELL_Y + BELL_RY + 2, PAD_BOTTOM + PAD_RY + 2),
        tune = compose(TUNE[courseKey] or TUNE.school),
        pads = {},
        state = "idle",
        tries = TRIES,
        lit = {},
        seed = util.hash01(x, y, 5) * 1000,
    }, S)
    -- Rising in reading order, so the square reads like a line of music would.
    for i = 1, #NOTES do
        s.pads[i] = {
            x = x + (i % 2 == 1 and -PAD_DX or PAD_DX),
            y = y + (i <= 2 and PAD_TOP or PAD_BOTTOM),
        }
    end
    return s
end

local function inside(px, py, cx, cy, rx, ry)
    local dx, dy = (px - cx) / rx, (py - cy) / ry
    return dx * dx + dy * dy <= 1
end

function S:padAt(px, py)
    for i, p in ipairs(self.pads) do
        if inside(px, py, p.x, p.y, PAD_RX, PAD_RY) then return i end
    end
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
        self.pos = self.pos + 1
        if self.pos > #self.tune then
            self.state = "won"
            game.pickups[#game.pickups + 1] =
                Pickup.new("heart", self.x, self.y + (PAD_TOP + PAD_BOTTOM) / 2)
            game.particles:burst(self.x, self.y + (PAD_TOP + PAD_BOTTOM) / 2, 10, Palette.red)
            game:say("BRAVO!")
            Sfx.play("accept")
        end
    else
        self:sour(i)
        self.tries = self.tries - 1
        self.pos = 1
        if self.tries <= 0 then
            self.state = "fading"
            self.t = 0
        end
    end
end

function S:update(dt, game, pen)
    for i, l in pairs(self.lit) do
        self.lit[i] = l > dt and l - dt or nil
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

    local bell = inside(p.x, p.y, self.x, self.y + BELL_Y, BELL_RX, BELL_RY)
    local drawn = pen and math.abs(pen.x - self.x) <= BELL_RX
        and math.abs(pen.y - (self.y + BELL_Y)) <= BELL_RY
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

local function ellipse(cx, cy, rx, ry, dotted)
    local n = math.floor(2 * math.pi * math.max(rx, ry) * 1.5)
    for k = 0, n - 1 do
        if not dotted or k % 4 == 0 then
            local a = 2 * math.pi * k / n
            dot(cx + math.cos(a) * rx + 0.5, cy + math.sin(a) * ry + 0.5)
        end
    end
end

local HEAD = { ".ooo.", "ooooo", ".ooo." }

function S:drawPad(i)
    local p = self.pads[i]
    local cx, cy = math.floor(p.x), math.floor(p.y)

    -- The stave a little high in its ring, since the heads hang under it.
    local sy = cy - 2
    colour(Palette.graphite)
    for l = -2, 2 do rect(cx - 8, sy + l * LINE, 17, 1) end

    local hot = self.flash == i and Palette.red
        or (self.lit[i] or self.state == "won") and Palette.blue
        or Palette.ink
    local hy = sy - NOTES[i].step * LINE / 2
    colour(hot)
    for r, row in ipairs(HEAD) do
        for c = 1, #row do
            if row:sub(c, c) == "o" then dot(cx - 3 + c, hy - 2 + r) end
        end
    end
    rect(cx + 2, hy - 7, 1, 7)

    if self.flash == i or self.lit[i] then
        colour(hot)
        ellipse(cx, cy, PAD_RX, PAD_RY)
        ellipse(cx, cy, PAD_RX + 1, PAD_RY + 1)
    elseif self.state == "won" then
        colour(Palette.blue)
        ellipse(cx, cy, PAD_RX, PAD_RY)
    else
        colour(Palette.graphite)
        ellipse(cx, cy, PAD_RX, PAD_RY, true)
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
    local bx = math.floor(self.x - #rows[1] / 2) + swing
    local by = math.floor(self.y + BELL_Y - #rows / 2)
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
        rect(self.x + BELL_RX + 2 + k * 3, self.y + BELL_Y - 2, 1, 5)
    end

    fade = 0
end

--- the page ------------------------------------------------------------------------

local KINDS = {
    tictactoe = function(x, y) return T.new(x, y) end,
    simon = function(x, y, game) return S.new(x, y, game.course.key) end,
}
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
        if math.abs(s.x - px) < ACTIVE and math.abs(s.y - py) < ACTIVE then
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

-- Whether a pickup at this point would land on a sheet, which the scatter
-- and the fixed pickups both ask before they put one down: a heart lying on a
-- tic-tac-toe cell is a prize and a puzzle each saying the other is not there.
function Worksheet.covers(game, x, y)
    if not game.worksheets then return false end
    for _, s in ipairs(game.worksheets) do
        if s.state ~= "gone" and math.abs(x - s.x) < s.hw + PAD and math.abs(y - s.y) < s.hh + PAD then
            return true
        end
    end
    return false
end

return Worksheet
